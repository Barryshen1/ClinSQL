WITH cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    pt.gender,
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age_admit,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_hospital,
    CASE 
      WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) < 8 THEN '<8' 
      ELSE '>=8' 
    END AS los_group,
    CASE 
      WHEN drg.drg_severity = 1 THEN 'low'
      WHEN drg.drg_severity = 2 THEN 'med'
      WHEN drg.drg_severity IN (3,4) THEN 'high'
      ELSE 'Unknown' 
    END AS comorbidity_burden,
    adm.hospital_expire_flag AS died_hospital,
    CASE WHEN icu.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS icu_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  INNER JOIN (
    SELECT DISTINCT hadm_id 
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
    WHERE 
      (icd_version = 9 AND icd_code LIKE '428%') 
      OR (icd_version = 10 AND icd_code LIKE 'I50%')
  ) hf ON adm.hadm_id = hf.hadm_id
  LEFT JOIN (
    SELECT hadm_id, drg_severity
    FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
    WHERE drg_type = 'APR'
  ) drg ON adm.hadm_id = drg.hadm_id
  LEFT JOIN (
    SELECT DISTINCT hadm_id 
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu ON adm.hadm_id = icu.hadm_id
  WHERE 
    pt.gender = 'F'
    AND pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) BETWEEN 51 AND 61
),

mv AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE itemid IN (227194, 225468, 225477)
  UNION DISTINCT
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE 
    (icd_version = 9 AND icd_code IN ('9670','9671','9672'))
    OR (icd_version = 10 AND icd_code IN ('0BH17EZ','0BH18EZ','0BJ08ZZ','0BT00ZZ','5A0935Z','5A0945Z','5A0955Z'))
),

vaso AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.inputevents`
  WHERE itemid IN (221906, 222168, 221289, 221750, 221662, 221653, 222315, 221749)
  UNION DISTINCT
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE 
    LOWER(medication) LIKE '%norepinephrine%' 
    OR LOWER(medication) LIKE '%epinephrine%'
    OR LOWER(medication) LIKE '%dopamine%'
    OR LOWER(medication) LIKE '%vasopressin%'
    OR LOWER(medication) LIKE '%phenylephrine%'
),

rrt AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE itemid IN (225802, 225803, 225805, 225809, 225810, 225815, 225816, 225825)
  UNION DISTINCT
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE 
    (icd_version = 9 AND icd_code IN ('3995','5498'))
    OR (icd_version = 10 AND icd_code IN ('5A1D00Z','5A1D60Z','5A1D70Z','5A1D80Z','5A1D90Z'))
),

cohort_outcomes AS (
  SELECT 
    c.*,
    CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS had_mv,
    CASE WHEN vaso.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS had_vaso,
    CASE WHEN rrt.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS had_rrt
  FROM cohort c
  LEFT JOIN mv ON c.hadm_id = mv.hadm_id
  LEFT JOIN vaso ON c.hadm_id = vaso.hadm_id
  LEFT JOIN rrt ON c.hadm_id = rrt.hadm_id
),

group_metrics AS (
  SELECT 
    icu_flag,
    los_group,
    comorbidity_burden,
    COUNT(*) AS total_patients,
    AVG(CAST(died_hospital AS FLOAT64)) * 100 AS mortality_rate,
    AVG(CAST(had_mv AS FLOAT64)) * 100 AS mv_prevalence,
    AVG(CAST(had_vaso AS FLOAT64)) * 100 AS vaso_prevalence,
    AVG(CAST(had_rrt AS FLOAT64)) * 100 AS rrt_prevalence
  FROM cohort_outcomes
  GROUP BY icu_flag, los_group, comorbidity_burden
),

mortality_comparison AS (
  SELECT 
    los_group,
    comorbidity_burden,
    MAX(IF(icu_flag=1, mortality_rate, NULL)) AS mortality_icu,
    MAX(IF(icu_flag=0, mortality_rate, NULL)) AS mortality_noicu
  FROM group_metrics
  GROUP BY los_group, comorbidity_burden
)

SELECT 
  gm.icu_flag,
  gm.los_group,
  gm.comorbidity_burden,
  gm.total_patients,
  gm.mortality_rate,
  gm.mv_prevalence,
  gm.vaso_prevalence,
  gm.rrt_prevalence,
  CASE 
    WHEN gm.icu_flag = 1 THEN mc.mortality_icu - mc.mortality_noicu 
    ELSE NULL 
  END AS abs_diff_mortality,
  CASE 
    WHEN gm.icu_flag = 1 AND mc.mortality_noicu > 0 
      THEN mc.mortality_icu / mc.mortality_noicu 
    ELSE NULL 
  END AS rel_diff_mortality
FROM group_metrics gm
LEFT JOIN mortality_comparison mc
  ON gm.los_group = mc.los_group
  AND gm.comorbidity_burden = mc.comorbidity_burden
ORDER BY icu_flag DESC, los_group, comorbidity_burden;