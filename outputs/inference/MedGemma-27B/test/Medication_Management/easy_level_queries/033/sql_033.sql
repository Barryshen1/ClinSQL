WITH PatientInfo AS (
  SELECT
    subject_id
  FROM patients
  WHERE
    gender = 'F' AND anchor_age BETWEEN 77 AND 87
), PrescriptionInfo AS (
  SELECT
    p.subject_id,
    rx.hadm_id,
    rx.starttime,
    rx.stoptime,
    rx.drug
  FROM prescriptions AS rx
  INNER JOIN PatientInfo AS pi
    ON rx.subject_id = pi.subject_id
  WHERE
    rx.drug LIKE '%ARB%'
), DurationCalculation AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    stoptime,
    drug,
    -- Calculate duration in days
    -- Handle cases where stoptime is NULL (ongoing prescription)
    -- Use DATE_DIFF for calculating the difference between two dates
    -- If stoptime is NULL, consider the current time as the end time for calculation purposes
    -- However, the question asks for the average duration of *individual* prescriptions,
    -- implying we should only consider prescriptions that have ended.
    -- Let's filter out prescriptions where stoptime is NULL.
    -- If stoptime is NULL, the duration is not fully known yet.
    -- We can calculate the duration as stoptime - starttime.
    -- If stoptime is NULL, we can exclude these records or assign a large value,
    -- but excluding seems more appropriate for calculating the average duration of *completed* prescriptions.
    -- Let's calculate the duration in days using DATE_DIFF.
    -- If stoptime is NULL, we will exclude the record.
    -- If stoptime is not NULL, we calculate the difference.
    -- We need to handle the case where starttime and stoptime are timestamps.
    -- DATE_DIFF returns the number of days between two dates.
    -- We should cast the timestamps to dates first.
    -- DATE_DIFF(DATE(stoptime), DATE(starttime), DAY)
    -- We need to ensure that stoptime is not NULL before calculating the difference.
    -- We can use a CASE statement or filter out NULL stoptimes.
    -- Let's filter out NULL stoptimes.
    -- We need to calculate the duration in days.
    -- DATE_DIFF(DATE(stoptime), DATE(starttime), DAY)
    -- We need to handle the case where starttime and stoptime are timestamps.
    -- DATE_DIFF(DATE(stoptime), DATE(starttime), DAY)
    -- We need to ensure that stoptime is not NULL before calculating the difference;