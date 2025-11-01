WITH durations AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.starttime,
    p.stoptime,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pat.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON p.subject_id = a.subject_id
   AND p.hadm_id = a.hadm_id
  WHERE LOWER(pat.gender) = 'm'
    -- age at admission (approx): anchor_age + (admit_year - anchor_year)
    AND (pat.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pat.anchor_year)) BETWEEN 38 AND 48
    -- ARB drugs (case-insensitive match; include common ARBs)
    AND (
      LOWER(p.drug) LIKE '%losartan%'    OR
      LOWER(p.drug) LIKE '%valsartan%'   OR
      LOWER(p.drug) LIKE '%irbesartan%'   OR
      LOWER(p.drug) LIKE '%candesartan%'  OR
      LOWER(p.drug) LIKE '%telmisartan%'  OR
      LOWER(p.drug) LIKE '%olmesartan%'   OR
      LOWER(p.drug) LIKE '%eprosartan%'   OR
      LOWER(p.drug) LIKE '%azilsartan%'
    )
    -- ensure we have a defined duration
    AND p.stoptime IS NOT NULL
    AND p.starttime IS NOT NULL
    AND TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) >= 0
)

SELECT
  quantiles[OFFSET(75)] AS p75_duration_days
FROM (
  SELECT APPROX_QUANTILES(duration_days, 100) AS quantiles
  FROM durations
) AS t;