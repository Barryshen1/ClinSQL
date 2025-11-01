WITH base_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_at_admit,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 51 AND 61
    AND a.dischtime > a.admittime
),
hf_admissions AS (
  SELECT DISTINCT ba.hadm_id
  FROM base_admissions ba
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON ba.hadm_id = d.hadm_id
  WHERE ((d.icd_version = 9 AND d.icd_code LIKE '428%')
     OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%'))
),
cohort AS (
  SELECT 
    ba.*,
    CASE WHEN EXISTS(
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
      WHERE i.hadm_id = ba.hadm_id
    ) THEN 1 ELSE 0 END AS icu_flag,
    CASE WHEN ba.los_days < 8 THEN '<8' ELSE '>=8' END AS los_cat
  FROM base_admissions ba
  INNER JOIN hf_admissions hf ON ba.hadm_id = hf.hadm_id
),
comorb_count AS (
  SELECT 
    c.*,
    COUNT(d.seq_num) AS num_comorb
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON c.hadm_id = d.hadm_id AND d.seq_num > 1
  GROUP BY 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag,
    c.gender, c.anchor_age, c.anchor_year, c.age_at_admit, c.los_days,
    c.icu_flag, c.los_cat
),
stratified_cohort AS (
  SELECT *,
    NTILE(3) OVER (ORDER BY num_comorb ASC) AS comorb_rank
  FROM comorb_count
),
mv_itemids AS (
  SELECT itemid FROM UNNEST([720, 223848, 223849, 224009, 224138, 224419, 225477, 225798, 226089, 227041]) AS itemid
),
vaso_itemids AS (
  SELECT itemid FROM UNNEST([220615, 220543, 220952, 228351, 227481, 221479]) AS itemid
),
rrt_itemids AS (
  SELECT itemid FROM UNNEST([225826, 220980, 228537]) AS itemid
),
flags_cohort AS (
  SELECT 
    sc.*,
    CASE WHEN sc.icu_flag = 1 AND EXISTS(
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      INNER JOIN mv_itemids m ON ce.itemid = m.itemid
      WHERE ce.hadm_id = sc.hadm_id
    ) THEN 1 ELSE 0 END AS mv_flag,
    CASE WHEN sc.icu_flag = 1 AND EXISTS(
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
      INNER JOIN vaso_itemids v ON ie.itemid = v.itemid
      WHERE ie.hadm_id = sc.hadm_id AND ie.amount > 0
    ) THEN 1 ELSE 0 END AS vaso_flag,
    CASE WHEN sc.icu_flag = 1 AND EXISTS(
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      INNER JOIN rrt_itemids r ON pe.itemid = r.itemid
      WHERE pe.hadm_id = sc.hadm_id
    ) THEN 1 ELSE 0 END AS rrt_flag
  FROM stratified_cohort sc
)
SELECT 
  icu_flag,
  los_cat,
  CASE comorb_rank 
    WHEN 1 THEN 'low' 
    WHEN 2 THEN 'med' 
    WHEN 3 THEN 'high' 
  END AS comorb_cat,
  COUNT(*) AS n_patients,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mort_rate_pct,
  ROUND(AVG(mv_flag) * 100, 2) AS mv_prevalence_pct,
  ROUND(AVG(vaso_flag) * 100, 2) AS vaso_prevalence_pct,
  ROUND(AVG(rrt_flag) * 100, 2) AS rrt_prevalence_pct
FROM flags_cohort
GROUP BY icu_flag, los_cat, comorb_rank
ORDER BY icu_flag, los_cat, comorb_rank;