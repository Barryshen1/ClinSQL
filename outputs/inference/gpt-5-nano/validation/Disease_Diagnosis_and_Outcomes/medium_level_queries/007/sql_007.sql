WITH
  -- 1) Eligible female patients aged 51-61 with heart failure
eligible AS (
  SELECT a.subject_id,
         a.hadm_id,
         a.admittime,
         a.dischtime,
         a.deathtime,
         a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
),

-- 2) HF admissions: map diagnoses_icd -> d_icd_diagnoses long_title
hf_adm AS (
  SELECT DISTINCT e.subject_id,
                  e.hadm_id,
                  e.admittime,
                  e.dischtime,
                  e.deathtime,
                  e.hospital_expire_flag
  FROM eligible e
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = e.subject_id
   AND di.hadm_id = e.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dd.icd_code = di.icd_code
   AND dd.icd_version = di.icd_version
  WHERE LOWER(dd.long_title) LIKE '%heart failure%'
),

-- 3) ICU exposure per admission
icu_flag AS (
  SELECT hadm_id, 1 AS icu_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),

icu_all AS (
  SELECT h.hadm_id,
         IFNULL(i.icu_flag, 0) AS icu_flag
  FROM hf_adm h
  LEFT JOIN icu_flag i
    ON h.hadm_id = i.hadm_id
),

-- 4) LOS (days)
los AS (
  SELECT hadm_id,
         (TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0) AS los_days
  FROM hf_adm
),

-- 5) In-hospital mortality
mort AS (
  SELECT hadm_id,
         CASE WHEN deathtime IS NOT NULL OR hospital_expire_flag = 1 THEN 1 ELSE 0 END AS in_hosp_mortality
  FROM hf_adm
),

-- 6) Comorbidity burden (rough: count of distinct ICDs excluding HF)
comorb AS (
  SELECT h.hadm_id,
         COUNT(DISTINCT di.icd_code) AS comorb_count
  FROM hf_adm h
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = h.subject_id
   AND di.hadm_id = h.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dd.icd_code = di.icd_code
   AND dd.icd_version = di.icd_version
  WHERE LOWER(dd.long_title) NOT LIKE '%heart failure%'
  GROUP BY h.hadm_id
),
comorb_group AS (
  SELECT hadm_id,
         NTILE(3) OVER (ORDER BY comorb_count) AS comorb_group
  FROM comorb
),

-- 7) Mechanical ventilation (mv) presence (ICU events) – heuristic by item label
mv AS (
  SELECT pe.hadm_id,
         1 AS mv_flag
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON di.itemid = pe.itemid
  WHERE LOWER(di.label) LIKE '%ventilation%'
     OR LOWER(di.label) LIKE '%endotracheal%'
  GROUP BY pe.hadm_id
),

-- 8) Vasoactive meds presence (ICU meds) – heuristic by item label
vaso AS (
  SELECT ie.hadm_id,
         1 AS vaso_flag
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON di.itemid = ie.itemid
  WHERE LOWER(di.label) LIKE '%norepinephrine%' OR
        LOWER(di.label) LIKE '%epinephrine%' OR
        LOWER(di.label) LIKE '%dopamine%' OR
        LOWER(di.label) LIKE '%vasopressin%' OR
        LOWER(di.label) LIKE '%phenylephrine%'
  GROUP BY ie.hadm_id
),

-- 9) Renal replacement therapy (RRT) presence – dialysis/CRRT related procedures
rrt AS (
  SELECT pe.hadm_id,
         1 AS rrt_flag
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON di.itemid = pe.itemid
  WHERE LOWER(di.label) LIKE '%renal replacement%' OR
        LOWER(di.label) LIKE '%dialysis%'
  GROUP BY pe.hadm_id
),

-- 10) Assemble per-admission features
adm_features AS (
  SELECT a.hadm_id,
         a.icu_flag,
         l.los_days,
         m.in_hosp_mortality,
         cg.comorb_group,
         IFNULL(mv.mv_flag, 0) AS mv_flag,
         IFNULL(vaso.vaso_flag, 0) AS vaso_flag,
         IFNULL(rrt.rrt_flag, 0) AS rrt_flag
  FROM icu_all a
  LEFT JOIN los l ON a.hadm_id = l.hadm_id
  LEFT JOIN mort m ON a.hadm_id = m.hadm_id
  LEFT JOIN comorb_group cg ON a.hadm_id = cg.hadm_id
  LEFT JOIN mv mv ON a.hadm_id = mv.hadm_id
  LEFT JOIN vaso vaso ON a.hadm_id = vaso.hadm_id
  LEFT JOIN rrt rrt ON a.hadm_id = rrt.hadm_id
)

SELECT
  CASE WHEN icu_flag = 1 THEN 'ICU' ELSE 'No ICU' END AS icu_group,
  CASE WHEN los_days < 8 THEN '<8 days' ELSE '>=8 days' END AS los_group,
  CASE comorb_group
     WHEN 1 THEN 'low'
     WHEN 2 THEN 'med'
     WHEN 3 THEN 'high'
  END AS comorb_group,
  COUNT(*) AS n_patients,
  SUM(in_hosp_mortality) AS deaths,
  AVG(in_hosp_mortality) AS mort_rate,
  AVG(mv_flag) AS mv_prevalence,
  AVG(vaso_flag) AS vaso_prevalence,
  AVG(rrt_flag) AS rrt_prevalence
FROM adm_features
GROUP BY icu_group, los_group, comorb_group
ORDER BY icu_group, los_group, comorb_group;