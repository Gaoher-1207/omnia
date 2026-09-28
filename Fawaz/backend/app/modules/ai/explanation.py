"""Concise, factual plan explanation derived after candidate validation.

Provider prose remains available in plan details; it never supplies the
prominent reasons. This module does not change scheduling or feasibility.
"""

from app.modules.ai.constraints import DEFAULT_TASK_MINUTES, minutes, window_start
from app.modules.ai.schemas import AIPlanContent, PlanContext, PlanExplanationOut


def explain_plan(content: AIPlanContent, context: PlanContext, unscheduled: list[dict]) -> PlanExplanationOut:
    task_by_ref = {task.ref: task for task in context.open_tasks}
    study_by_ref = {block.ref: block for block in context.study_blocks}
    scheduled_tasks = [task_by_ref[item.task_ref] for item in content.items if item.task_ref in task_by_ref]
    urgent_tasks = [task for task in scheduled_tasks if task.due_in_days is not None and task.due_in_days <= 1]
    study_minutes: dict[str, int] = {}
    for item in content.items:
        if item.study_ref in study_by_ref:
            subject = study_by_ref[item.study_ref].subject
            study_minutes[subject] = study_minutes.get(subject, 0) + minutes(item.end) - minutes(item.start)
    imminent_exams = sorted(
        (exam for exam in context.exams if exam.days_left <= 7 and study_minutes.get(exam.subject)),
        key=lambda exam: exam.days_left,
    )
    reasons: list[str] = []
    if urgent_tasks:
        task = min(urgent_tasks, key=lambda value: (value.due_in_days, value.due_time or "23:59"))
        due = "today" if task.due_in_days == 0 else "tomorrow" if task.due_in_days == 1 else "overdue"
        reasons.append(
            f"Task {task.title} is due {due}; "
            f"its {task.estimated_minutes or DEFAULT_TASK_MINUTES}-minute block is reserved."
        )
    if imminent_exams:
        exam = imminent_exams[0]
        when = "today" if exam.days_left == 0 else "tomorrow" if exam.days_left == 1 else f"in {exam.days_left} days"
        reasons.append(f"{exam.subject} exam is {when}; {study_minutes[exam.subject]} min of revision is scheduled.")
    if not urgent_tasks and scheduled_tasks:
        reasons.append(f"{len(scheduled_tasks)} task{'s' if len(scheduled_tasks) != 1 else ''} have reserved time.")
    start, end = window_start(context), context.planning_end_minutes
    if context.commitments and end > start:
        largest = max(
            context.commitments,
            key=lambda commitment: max(
                0, min(end, commitment.end_minutes) - max(start, commitment.start_minutes)
            ),
        )
        occupied = max(0, min(end, largest.end_minutes) - max(start, largest.start_minutes))
        if occupied >= 60 and occupied * 4 >= end - start:
            reasons.append(f"{largest.title} reserves {occupied} min of the remaining planning window.")
    remaining = sum(work["remaining_minutes"] for work in unscheduled)
    if remaining:
        reasons.append(f"{remaining} min of requested work remains unscheduled.")
    if len(reasons) < 3:
        workout = next((item for item in content.items if item.category == "fitness"), None)
        if workout:
            duration = minutes(workout.end) - minutes(workout.start)
            reasons.append(f"A {duration}-minute activity block is included.")
    reasons = reasons[:3]
    if urgent_tasks:
        headline = "Nearby task deadlines shape this plan."
    elif imminent_exams:
        headline = "Upcoming exam revision shapes this plan."
    elif context.commitments and any("reserves" in reason for reason in reasons):
        headline = "Fixed commitments shape the available time today."
    elif remaining and not content.items:
        headline = "Some requested work remains unscheduled."
    elif content.items:
        headline = "Today's work is arranged within your planning hours."
    else:
        headline = "There is no work scheduled in the remaining window."
    supporting = []
    sleep = context.last_night_sleep
    if sleep and sleep.minutes < 360:
        supporting.append(f"Last night's logged sleep was {sleep.minutes // 60}h {sleep.minutes % 60:02d}m.")
    step_goal = context.goals.get("steps", 0)
    if step_goal:
        supporting.append(f"Steps logged: {context.today.steps:,} of {step_goal:,} target.")
    return PlanExplanationOut(headline=headline, key_reasons=reasons, supporting_context=supporting)
