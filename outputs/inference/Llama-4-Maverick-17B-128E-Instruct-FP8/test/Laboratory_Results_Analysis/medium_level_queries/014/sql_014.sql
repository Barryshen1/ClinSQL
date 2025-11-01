WITH 
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 79 AND 89
),
acs_admissions AS (
  SELECT DISTINCT diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  JOIN eligible_patients ep ON diag.subject_id = ep.subject_id
  WHERE (d_icd.long_title LIKE '%myocardial infarction%' OR d_icd.long_title LIKE '%unstable angina%')
),
troponin_t_results AS (
  SELECT labevents.hadm_id, labevents.valuenum, 
         ROW_NUMBER() OVER (PARTITION BY labevents.hadm_id ORDER BY labevents.charttime) as rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` labevents
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d_labitems
    ON labevents.itemid = d_labitems.itemid
  WHERE labevents.hadm_id IN (SELECT hadm_id FROM acs_admissions)
    AND d_labitems.label LIKE '%Troponin T%'
),
categorized_results AS (
  SELECT hadm_id, valuenum,
         CASE
           WHEN valuenum < 0.01 THEN 'Normal'
           WHEN valuenum BETWEEN 0.01 AND 0.03 THEN 'Borderline'
           ELSE 'Elevated'
         END AS category
  FROM troponin_t_results
  WHERE rn = 1
)
SELECT category, COUNT(*) as count, 
       ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM categorized_results), 2) as percentage
FROM categorized_results
GROUP BY category;