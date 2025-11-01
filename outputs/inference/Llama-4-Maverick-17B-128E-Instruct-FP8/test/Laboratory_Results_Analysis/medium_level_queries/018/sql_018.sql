WITH troponin_t_itemid AS (
  SELECT itemid FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` WHERE label LIKE '%Troponin T%'
),
acs_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 90 AND 100
  AND d_diag.long_title LIKE '%Acute coronary syndrome%'
),
troponin_t_results AS (
  SELECT a.hadm_id, 
         l.valuenum, 
         l.ref_range_lower, 
         l.ref_range_upper,
         CASE
           WHEN l.valuenum <= l.ref_range_upper * 1.1 THEN 'normal'
           WHEN l.valuenum > l.ref_range_upper * 1.1 AND l.valuenum <= l.ref_range_upper * 2 THEN 'borderline'
           ELSE 'elevated'
         END AS troponin_t_category
  FROM acs_patients a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON a.hadm_id = l.hadm_id
  WHERE l.itemid IN (SELECT itemid FROM troponin_t_itemid)
  AND l.charttime = (SELECT MIN(charttime) FROM `physionet-data.mimiciv_3_1_hosp.labevents` l2 WHERE l2.hadm_id = l.hadm_id AND l2.itemid = l.itemid)
),
length_of_stay AS (
  SELECT hadm_id, DATETIME_DIFF(dischtime, admittime, HOUR) / 24 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
)
SELECT 
  t.troponin_t_category,
  COUNT(t.hadm_id) AS count,
  COUNT(t.hadm_id) * 100.0 / (SELECT COUNT(DISTINCT hadm_id) FROM acs_patients) AS percentage,
  AVG(los) AS mean_los
FROM troponin_t_results t
INNER JOIN length_of_stay l ON t.hadm_id = l.hadm_id
GROUP BY t.troponin_t_category;