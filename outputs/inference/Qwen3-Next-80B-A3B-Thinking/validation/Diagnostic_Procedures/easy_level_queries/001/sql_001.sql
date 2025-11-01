WITH target_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 63 AND 73
),
cardiac_procedures AS (
  SELECT p.hadm_id, COUNT(DISTINCT p.icd_code) AS num_cardiac_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE d.long_title LIKE '%cardiac%'
     OR d.long_title LIKE '%heart%'
     OR d.long_title LIKE '%coronary%'
     OR d.long_title LIKE '%myocardial%'
     OR d.long_title LIKE '%valve%'
     OR d.long_title LIKE '%aortic%'
     OR d.long_title LIKE '%bypass%'
     OR d.long_title LIKE '%angioplasty%'
  GROUP BY p.hadm_id
)
SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY num_cardiac_procedures) AS percentile_75
FROM cardiac_procedures cp
JOIN target_admissions ta ON cp.hadm_id = ta.hadm_id;