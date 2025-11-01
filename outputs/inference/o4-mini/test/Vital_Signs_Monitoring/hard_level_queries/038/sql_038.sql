WITH
-- 1. Identify status epilepticus ICD codes
se_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%status epileptic%'
),

-- 2. Build ICU cohort with status epilepticus
se_cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.subject_id = adm.subject_id
   AND icu.hadm_id    = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON icu.subject_id = pt.subject_id
  WHERE pt.gender = 'F'
    AND pt.anchor_age BETWEEN 63 AND 73
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      JOIN se_codes sc
        ON dx.icd_code    = sc.icd_code
       AND dx.icd_version = sc.icd_version
      WHERE dx.hadm_id = icu.hadm_id
    )
    AND TIMESTAMP_DIFF(icu.intime, adm.admittime, HOUR) <= 72
),

-- 3. General ICU comparator cohort
all_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.subject_id = adm.subject_id
   AND icu.hadm_id    = adm.hadm_id
),

-- 4. Identify relevant itemids for HR and MAP
vitals_items AS (
  SELECT
    itemid,
    CASE
      WHEN LOWER(label) LIKE '%heart rate%' THEN 'hr'
      WHEN LOWER(label) LIKE '%mean arterial pressure%' THEN 'map'
    END AS vital
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%heart rate%'
     OR LOWER(label) LIKE '%mean arterial pressure%'
),

-- 5. Extract vitals in first 72h for both cohorts
vitals AS (
  SELECT
    c.cohort_name,
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    vi.vital,
    v.valuenum
  FROM (
    SELECT 'status_epilepticus' AS cohort_name, * FROM se_cohort
    UNION ALL
    SELECT 'all_icu'              AS cohort_name, * FROM all_icu
  ) AS c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` v
    ON c.subject_id = v.subject_id
   AND c.hadm_id    = v.hadm_id
   AND c.stay_id    = v.stay_id
  JOIN vitals_items vi
    ON v.itemid = vi.itemid
  WHERE v.charttime BETWEEN c.intime
                      AND TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
    AND SAFE_CAST(v.valuenum AS FLOAT64) IS NOT NULL
),

-- 6. Compute per‐stay metrics
per_stay AS (
  SELECT
    v.cohort_name,
    c.stay_id,
    c.los,
    c.hospital_expire_flag,
    -- fraction of HR readings >100
    AVG(CASE WHEN vital = 'hr'  AND valuenum > 100 THEN 1.0 ELSE 0.0 END) AS tachy_burden,
    -- fraction of MAP readings <65
    AVG(CASE WHEN vital = 'map' AND valuenum <  65 THEN 1.0 ELSE 0.0 END) AS map65_burden,
    -- approximated instability index = stddev of all HR+MAP
    STDDEV_POP(valuenum) AS vit_instability_index
  FROM vitals v
  JOIN (
    SELECT stay_id, los, hospital_expire_flag FROM se_cohort
    UNION ALL
    SELECT stay_id, los, hospital_expire_flag FROM all_icu
  ) AS c
    ON v.stay_id = c.stay_id
  GROUP BY v.cohort_name, c.stay_id, c.los, c.hospital_expire_flag
),

-- 7. Summarize each cohort
summary AS (
  SELECT
    cohort_name,
    -- vit_instability_index: mean and quantiles
    AVG(vit_instability_index) AS vi_mean,
    APPROX_QUANTILES(vit_instability_index, 100)[OFFSET(25)] AS vi_p25,
    APPROX_QUANTILES(vit_instability_index, 100)[OFFSET(50)] AS vi_p50,
    APPROX_QUANTILES(vit_instability_index, 100)[OFFSET(75)] AS vi_p75,
    APPROX_QUANTILES(vit_instability_index, 100)[OFFSET(90)] AS vi_p90,
    -- average tachycardia burden
    AVG(tachy_burden) AS avg_tachy_burden,
    -- average MAP<65 burden
    AVG(map65_burden) AS avg_map65_burden,
    -- average ICU LOS
    AVG(los) AS avg_los_days,
    -- mortality rate
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM per_stay
  GROUP BY cohort_name
)

SELECT *
FROM summary
ORDER BY cohort_name;