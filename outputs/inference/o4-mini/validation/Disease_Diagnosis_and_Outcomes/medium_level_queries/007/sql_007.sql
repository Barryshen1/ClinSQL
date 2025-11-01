WITH
-- 1. Base cohort: female patients age 51-61 with any heart failure diagnosis
hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CASE WHEN ic.stay_id IS NOT NULL THEN 1 ELSE 0 END AS ICU_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic
      ON a.hadm_id = ic.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND LOWER(dd.long_title) LIKE '%heart failure%'
  GROUP BY
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    ic.stay_id
),

-- 2. Compute comorbidity counts (distinct diagnoses per admission)
comorbidity_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS comorb_cnt
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    hadm_id IN (SELECT hadm_id FROM hf_admissions)
  GROUP BY hadm_id
),

-- 3. Assign tertiles to comorbidity burden
comorbidity_tertiles AS (
  SELECT
    hadm_id,
    comorb_cnt,
    NTILE(3) OVER (ORDER BY comorb_cnt) AS tertile
  FROM
    comorbidity_counts
),

-- 4. Combine and derive categories
admissions_with_strata AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    IF(h.ICU_flag = 1, 'ICU', 'no_ICU') AS ICU_group,
    IF(h.los_days < 8, '<8', '>=8') AS LOS_group,
    CASE c.tertile
      WHEN 1 THEN 'low'
      WHEN 2 THEN 'med'
      WHEN 3 THEN 'high'
    END AS comorb_group,
    h.hospital_expire_flag
  FROM
    hf_admissions h
    JOIN comorbidity_tertiles c
      ON h.hadm_id = c.hadm_id
),

-- 5. MV indicator
mv_flag AS (
  SELECT DISTINCT
    pc.hadm_id,
    1 AS mv
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pc
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON pc.icd_code = dp.icd_code
      AND pc.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%ventilation%'
),

-- 6. Vasopressor indicator
vaso_flag AS (
  SELECT DISTINCT
    hadm_id,
    1 AS vaso
  FROM
    `physionet-data.mimiciv_3_1_icu.inputevents`
  WHERE
    LOWER(CAST(ordercategorydescription AS STRING)) LIKE '%vasopressor%'
    AND hadm_id IN (SELECT hadm_id FROM admissions_with_strata)
),

-- 7. RRT indicator
rrt_flag AS (
  SELECT DISTINCT
    hadm_id,
    1 AS rrt
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE
    LOWER(CAST(value AS STRING)) LIKE '%dialysis%'
    AND hadm_id IN (SELECT hadm_id FROM admissions_with_strata)
)

-- 8. Final aggregation
SELECT
  s.ICU_group,
  s.LOS_group,
  s.comorb_group,
  COUNT(*) AS n_admissions,
  ROUND(100 * SAFE_DIVIDE(SUM(s.hospital_expire_flag), COUNT(*)), 1) AS mort_rate_pct,
  -- reference group is non-ICU, LOS<8, low
  ROUND(
    100 * SAFE_DIVIDE(
      SUM(s.hospital_expire_flag) - 
      (SELECT SUM(hospital_expire_flag)
       FROM admissions_with_strata
       WHERE ICU_group = 'no_ICU' AND LOS_group = '<8' AND comorb_group = 'low'
      ),
      COUNT(*)
    ), 1
  ) AS abs_diff_mort_pct,
  ROUND(
    SAFE_DIVIDE(
      SAFE_DIVIDE(SUM(s.hospital_expire_flag), COUNT(*)),
      SAFE_DIVIDE(
        (SELECT SUM(hospital_expire_flag)
         FROM admissions_with_strata
         WHERE ICU_group = 'no_ICU' AND LOS_group = '<8' AND comorb_group = 'low'
        ),
        (SELECT COUNT(*) 
         FROM admissions_with_strata
         WHERE ICU_group = 'no_ICU' AND LOS_group = '<8' AND comorb_group = 'low'
        )
      )
    ), 2
  ) AS rel_diff_mort_ratio,
  ROUND(100 * SAFE_DIVIDE(SUM(IF(mv.mv = 1, 1, 0)), COUNT(*)), 1)   AS mv_pct,
  ROUND(100 * SAFE_DIVIDE(SUM(IF(vs.vaso = 1, 1, 0)), COUNT(*)), 1) AS vaso_pct,
  ROUND(100 * SAFE_DIVIDE(SUM(IF(rrt.rrt = 1, 1, 0)), COUNT(*)), 1) AS rrt_pct
FROM
  admissions_with_strata s
  LEFT JOIN mv_flag mv ON s.hadm_id = mv.hadm_id
  LEFT JOIN vaso_flag vs ON s.hadm_id = vs.hadm_id
  LEFT JOIN rrt_flag rrt ON s.hadm_id = rrt.hadm_id
GROUP BY
  ICU_group,
  LOS_group,
  comorb_group
ORDER BY
  ICU_group,
  LOS_group,
  comorb_group;