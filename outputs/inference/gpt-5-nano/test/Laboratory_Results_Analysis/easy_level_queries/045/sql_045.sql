WITH sepsis_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
    ON d.icd_code = ddi.icd_code
   AND d.icd_version = ddi.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON d.subject_id = p.subject_id
  WHERE LOWER(ddi.long_title) LIKE '%sepsis%'
    AND p.gender = 'Male'
),

creatinine_per_adm AS (
  SELECT s.subject_id, s.hadm_id, MAX(l.valuenum) AS max_creatinine
  FROM sepsis_admissions AS s
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON s.subject_id = l.subject_id
   AND s.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON l.itemid = dli.itemid
  WHERE LOWER(dli.label) LIKE '%creatinine%'
    AND (dli.fluid = 'serum' OR LOWER(dli.fluid) LIKE '%serum%')
  GROUP BY s.subject_id, s.hadm_id
)

SELECT ca.hadm_id,
       ca.subject_id,
       ca.max_creatinine,
       a.admittime
FROM creatinine_per_adm AS ca
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  ON ca.hadm_id = a.hadm_id
ORDER BY ca.max_creatinine DESC
LIMIT 1;