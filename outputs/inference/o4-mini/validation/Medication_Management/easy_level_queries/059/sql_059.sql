SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] AS arb_duration_75th_pct_day
FROM (
  SELECT
    DATE_DIFF(DATE(pres.stoptime), DATE(pres.starttime), DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON pat.subject_id = adm.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
      ON pres.subject_id = adm.subject_id
     AND pres.hadm_id   = adm.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 38 AND 48
    AND pres.starttime IS NOT NULL
    AND pres.stoptime  IS NOT NULL
    AND pres.starttime >= adm.admittime
    AND pres.stoptime  <= adm.dischtime
    AND LOWER(pres.drug) LIKE '%sartan%'
    -- Ensure only positive durations
    AND DATE_DIFF(DATE(pres.stoptime), DATE(pres.starttime), DAY) > 0
);