WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 82 AND 92
),
relevant_icd_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE icd_version = 9 AND (long_title LIKE '%pacemaker%' OR long_title LIKE '%implantable cardioverter-defibrillator%')
  UNION DISTINCT
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE icd_version = 10 AND (long_title LIKE '%pacemaker%' OR long_title LIKE '%implantable cardioverter-defibrillator%')
),
procedures AS (
  SELECT p.hadm_id, p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN filtered_patients fp ON p.subject_id = fp.subject_id
  INNER JOIN relevant_icd_codes ric ON p.icd_code = ric.icd_code
)
SELECT MIN(num_procedures) AS min_procedures
FROM (
  SELECT hadm_id, COUNT(DISTINCT icd_code) AS num_procedures
  FROM procedures
  GROUP BY hadm_id
);