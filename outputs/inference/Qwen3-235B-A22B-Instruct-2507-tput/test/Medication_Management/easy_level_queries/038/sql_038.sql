WITH digoxin_duration AS (
  SELECT
    DATETIME_DIFF(pres.stoptime, pres.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.prescriptions pres
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions adm
    ON pres.hadm_id = adm.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.patients pat
    ON adm.subject_id = pat.subject_id
  WHERE
    LOWER(pres.drug) = 'digoxin'
    AND pat.gender = 'M'
    AND pres.stoptime IS NOT NULL
    AND pres.starttime IS NOT NULL
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 36 AND 46
)
SELECT
  PERCENTILE_CONT(duration_days, 0.75) OVER () - PERCENTILE_CONT(duration_days, 0.25) OVER () AS iqr_duration_days
FROM
  digoxin_duration
LIMIT 1;