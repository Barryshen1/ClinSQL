WITH target_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 44 AND 54
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('4350','4351','4352','4353','4358','4359'))
          OR
          (d.icd_version = 10 AND d.icd_code IN ('G45.0','G45.1','G45.2','G45.3','G45.4','G45.8','G45.9'))
        )
    )
),
imaging_counts AS (
  SELECT 
    hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE 
    (icd_version = 9 AND (icd_code LIKE '88%' OR icd_code LIKE '89%'))
    OR
    (icd_version = 10 AND (icd_code LIKE 'B%' OR icd_code LIKE 'C%'))
  GROUP BY hadm_id
),
icu_use_flag AS (
  SELECT 
    hadm_id,
    1 AS icu_use
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
admission_details AS (
  SELECT 
    ta.hadm_id,
    DATE_DIFF(CAST(ta.dischtime AS DATE), CAST(ta.admittime AS DATE), DAY) AS los_days,
    COALESCE(iu.icu_use, 0) AS icu_use,
    COALESCE(ic.imaging_count, 0) AS imaging_count
  FROM target_admissions ta
  LEFT JOIN icu_use_flag iu
    ON ta.hadm_id = iu.hadm_id
  LEFT JOIN imaging_counts ic
    ON ta.hadm_id = ic.hadm_id
),
filtered_admissions AS (
  SELECT 
    hadm_id,
    los_days,
    icu_use,
    imaging_count,
    CASE 
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7'
    END AS los_group
  FROM admission_details
  WHERE los_days BETWEEN 1 AND 7
)
SELECT 
  los_group,
  icu_use,
  APPROX_QUANTILES(imaging_count, 1000)[OFFSET(250)] AS p25,
  APPROX_QUANTILES(imaging_count, 1000)[OFFSET(500)] AS p50,
  APPROX_QUANTILES(imaging_count, 1000)[OFFSET(750)] AS p75
FROM filtered_admissions
GROUP BY los_group, icu_use
ORDER BY los_group, icu_use;