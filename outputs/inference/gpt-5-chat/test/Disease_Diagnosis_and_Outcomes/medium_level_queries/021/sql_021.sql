WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    CASE WHEN icu.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS icu_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON adm.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  LEFT JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu
    ON adm.hadm_id = icu.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 60 AND 70
    AND LOWER(dd.long_title) LIKE '%postoperative%'
),
charlson AS (
  SELECT
    hadm_id,
    SUM(charlson_score) AS cci
  FROM (
    SELECT
      di.hadm_id,
      CASE
        WHEN (di.icd_version = 9 AND di.icd_code BETWEEN '4280' AND '4289')
          OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%') THEN 1 -- CHF
        WHEN (di.icd_version = 9 AND di.icd_code BETWEEN '5850' AND '5859')
          OR (di.icd_version = 10 AND di.icd_code LIKE 'N18%') THEN 2 -- CKD
        WHEN (di.icd_version = 9 AND di.icd_code BETWEEN '2500' AND '2509')
          OR (di.icd_version = 10 AND di.icd_code LIKE 'E10%' OR di.icd_code LIKE 'E11%') THEN 1 -- Diabetes
        ELSE 0
      END AS charlson_score
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  )
  GROUP BY hadm_id
),
cohort_with_cci AS (
  SELECT
    c.*,
    IFNULL(ch.cci,0) AS cci
  FROM cohort c
  LEFT JOIN charlson ch
    ON c.hadm_id = ch.hadm_id
),
categorized AS (
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1–3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4–7'
      WHEN los_days >= 8 THEN '≥8'
      ELSE 'unknown'
    END AS los_bin,
    CASE
      WHEN cci <= 3 THEN '≤3'
      WHEN cci BETWEEN 4 AND 5 THEN '4–5'
      WHEN cci > 5 THEN '>5'
      ELSE 'unknown'
    END AS cci_bin,
    CASE
      WHEN hospital_expire_flag = 1 AND deathtime IS NOT NULL
        THEN DATE_DIFF(deathtime, admittime, DAY)
      ELSE NULL
    END AS time_to_death_days
  FROM cohort_with_cci
)

SELECT
  icu_flag,
  los_bin,
  cci_bin,
  COUNT(*) AS N,
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS mortality_pct,
  APPROX_QUANTILES(time_to_death_days, 100)[OFFSET(50)] AS median_time_to_death_days
FROM categorized
GROUP BY icu_flag, los_bin, cci_bin
ORDER BY icu_flag, los_bin, cci_bin;