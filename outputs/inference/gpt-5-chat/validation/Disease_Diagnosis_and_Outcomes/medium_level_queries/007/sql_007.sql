WITH hf_cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id,
    p.gender, p.anchor_age, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND (
      (d.icd_version = 9 AND (
         d.icd_code LIKE '428%' OR d.icd_code = '39891'
      ))
      OR
      (d.icd_version = 10 AND (
         d.icd_code LIKE 'I50%' OR d.icd_code IN ('I110','I130','I132')
      ))
    )
),
comorb_counts AS (
  SELECT hadm_id,
         COUNT(DISTINCT LEFT(icd_code,3)) AS comorb_n
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
comorb_group AS (
  SELECT hadm_id,
    CASE 
      WHEN comorb_n <= 1 THEN 'low'
      WHEN comorb_n BETWEEN 2 AND 3 THEN 'med'
      ELSE 'high'
    END AS comorb_cat
  FROM comorb_counts
),
icu_flag AS (
  SELECT hadm_id, 1 AS icu_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
los_group AS (
  SELECT hadm_id,
    CASE 
      WHEN DATETIME_DIFF(dischtime, admittime, DAY) < 8 THEN '<8'
      ELSE '>=8'
    END AS los_cat
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
mv_flag AS (
  SELECT DISTINCT pe.hadm_id, 1 AS mv
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%vent%'
),
vaso_flag AS (
  SELECT DISTINCT ie.hadm_id, 1 AS vaso
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%norepinephrine%'
     OR LOWER(di.label) LIKE '%epinephrine%'
     OR LOWER(di.label) LIKE '%dopamine%'
     OR LOWER(di.label) LIKE '%vasopressin%'
     OR LOWER(di.label) LIKE '%phenylephrine%'
),
rrt_flag AS (
  SELECT DISTINCT pe.hadm_id, 1 AS rrt
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%dialysis%'
     OR LOWER(di.label) LIKE '%continuous veno%'
     OR LOWER(di.label) LIKE '%cvvh%'
)
SELECT 
  COALESCE(i.icu_flag,0) AS icu_flag,
  l.los_cat,
  cg.comorb_cat,
  COUNT(*) AS n_admissions,
  SUM(h.hospital_expire_flag) AS deaths,
  ROUND(SUM(h.hospital_expire_flag)/COUNT(*)*100,1) AS mort_rate_pct,
  SUM(COALESCE(mv.mv,0)) AS mv_count,
  ROUND(SUM(COALESCE(mv.mv,0))/COUNT(*)*100,1) AS mv_pct,
  SUM(COALESCE(v.vaso,0)) AS vaso_count,
  ROUND(SUM(COALESCE(v.vaso,0))/COUNT(*)*100,1) AS vaso_pct,
  SUM(COALESCE(r.rrt,0)) AS rrt_count,
  ROUND(SUM(COALESCE(r.rrt,0))/COUNT(*)*100,1) AS rrt_pct
FROM hf_cohort h
LEFT JOIN comorb_group cg ON h.hadm_id = cg.hadm_id
LEFT JOIN icu_flag i ON h.hadm_id = i.hadm_id
LEFT JOIN los_group l ON h.hadm_id = l.hadm_id
LEFT JOIN mv_flag mv ON h.hadm_id = mv.hadm_id
LEFT JOIN vaso_flag v ON h.hadm_id = v.hadm_id
LEFT JOIN rrt_flag r ON h.hadm_id = r.hadm_id
GROUP BY icu_flag, l.los_cat, cg.comorb_cat
ORDER BY icu_flag DESC, l.los_cat, cg.comorb_cat;