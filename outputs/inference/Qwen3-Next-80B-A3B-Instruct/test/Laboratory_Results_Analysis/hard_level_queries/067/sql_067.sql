WITH acs_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND (
      did.icd_code LIKE '410%' OR
      did.icd_code LIKE '411%' OR
      did.icd_code LIKE '413%' OR
      did.icd_code LIKE 'I21%' OR
      did.icd_code LIKE 'I24%' OR
      did.icd_code = 'I20.0'
    )
),

-- CTE: Identify control patients (same age/gender, no ACS)
control_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
        ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          did.icd_code LIKE '410%' OR
          did.icd_code LIKE '411%' OR
          did.icd_code LIKE '413%' OR
          did.icd_code LIKE 'I21%' OR
          did.icd_code LIKE 'I24%' OR
          did.icd_code = 'I20.0'
        )
    )
),

-- CTE: Compute 72-hour lab instability score (distinct critical lab categories per admission)
lab_instability AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT dl.category) AS critical_lab_categories
  FROM acs_patients a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE le.charttime >= a.admittime
    AND le.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND (
      le.valuenum < le.ref_range_lower
      OR le.valuenum > le.ref_range_upper
      OR le.flag IN ('abnormal', 'high', 'low')
    )
  GROUP BY a.hadm_id
),

-- CTE: Compute instability score for control cohort
control_lab_instability AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT dl.category) AS critical_lab_categories
  FROM control_patients a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE le.charttime >= a.admittime
    AND le.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND (
      le.valuenum < le.ref_range_lower
      OR le.valuenum > le.ref_range_upper
      OR le.flag IN ('abnormal', 'high', 'low')
    )
  GROUP BY a.hadm_id
),

-- CTE: Assign quartiles to ACS cohort
acs_with_quartiles AS (
  SELECT
    li.critical_lab_categories,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    NTILE(4) OVER (ORDER BY li.critical_lab_categories) AS quartile
  FROM acs_patients a
  JOIN lab_instability li ON a.hadm_id = li.hadm_id
)

-- Final Result Set 1: Quartile breakdown (mortality % and avg LOS per quartile)
SELECT
  quartile,
  AVG(CAST(hospital_expire_flag AS FLOAT)) * 100 AS mortality_pct,
  AVG(los_days) AS avg_los_days
FROM acs_with_quartiles
GROUP BY quartile
ORDER BY quartile;

-- Final Result Set 2: Comparison of average critical lab categories (ACS vs Control)
SELECT
  'ACS' AS cohort,
  AVG(critical_lab_categories) AS avg_critical_lab_categories
FROM lab_instability
UNION ALL
SELECT
  'Control' AS cohort,
  AVG(critical_lab_categories) AS avg_critical_lab_categories
FROM control_lab_instability
ORDER BY cohort = 'ACS' DESC;