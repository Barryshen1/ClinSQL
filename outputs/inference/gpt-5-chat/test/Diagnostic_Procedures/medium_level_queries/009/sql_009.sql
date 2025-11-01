WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
    AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '435%') -- ICD-9 TIA
      OR (d.icd_version = 10 AND d.icd_code LIKE 'G45%') -- ICD-10 TIA
    )
),
cohort_los AS (
  SELECT
    c.*,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7'
    END AS los_group
  FROM cohort c
  WHERE los_days BETWEEN 1 AND 7
),
imaging_counts AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  WHERE
    (p.icd_version = 9 AND (p.icd_code LIKE '87%' OR p.icd_code LIKE '88%'))
    OR (p.icd_version = 10 AND p.icd_code LIKE 'B0%')
  GROUP BY p.subject_id, p.hadm_id
),
icu_flags AS (
  SELECT
    hadm_id,
    1 AS icu_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
joined AS (
  SELECT
    cl.subject_id,
    cl.hadm_id,
    cl.los_group,
    IF(IFNULL(i.icu_flag,0) = 1, 'ICU', 'No ICU') AS icu_use,
    IFNULL(ic.imaging_count, 0) AS imaging_count
  FROM cohort_los cl
  LEFT JOIN imaging_counts ic
    ON cl.subject_id = ic.subject_id
    AND cl.hadm_id = ic.hadm_id
  LEFT JOIN icu_flags i
    ON cl.hadm_id = i.hadm_id
)
SELECT
  los_group,
  icu_use,
  q[OFFSET(1)] AS p25,
  q[OFFSET(2)] AS p50,
  q[OFFSET(3)] AS p75
FROM (
  SELECT
    los_group,
    icu_use,
    APPROX_QUANTILES(imaging_count, 4) AS q
  FROM joined
  GROUP BY los_group, icu_use
)
ORDER BY los_group, icu_use;