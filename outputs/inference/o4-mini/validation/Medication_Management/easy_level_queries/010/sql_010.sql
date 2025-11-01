SELECT
  STDDEV_SAMP(duration_days) AS sd_nitrate_duration_days
FROM (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    TIMESTAMP_DIFF(
      LEAST(pr.stoptime, a.dischtime),
      GREATEST(pr.starttime, a.admittime),
      DAY
    ) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON pat.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON pr.subject_id = a.subject_id
     AND pr.hadm_id     = a.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 73 AND 83
    -- restrict to inpatient window
    AND pr.starttime BETWEEN a.admittime AND a.dischtime
    AND pr.stoptime IS NOT NULL
    -- optionally truncate stoptime after discharge
    AND pr.starttime < a.dischtime
    -- nitrate medications
    AND LOWER(pr.drug) LIKE '%nitro%'
)
WHERE duration_days > 0;