WITH qualifying_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
    ON a.hadm_id = d_icd.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON d_icd.icd_code = d.icd_code AND d_icd.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
  GROUP BY a.hadm_id
  HAVING SUM(CASE WHEN LOWER(d.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END) >= 1
     AND SUM(CASE WHEN LOWER(d.long_title) LIKE '%copd%' OR LOWER(d.long_title) LIKE '%chronic obstructive pulmonary disease%' THEN 1 ELSE 0 END) >= 1
)
SELECT STDDEV(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS sd_hospital_los_days
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN qualifying_admissions qa ON a.hadm_id = qa.hadm_id;