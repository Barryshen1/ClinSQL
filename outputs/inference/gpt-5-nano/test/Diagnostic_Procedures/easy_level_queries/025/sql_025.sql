WITH eligible AS (
  -- Female patients aged 40-50
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'Female'
    AND anchor_age BETWEEN 40 AND 50
),
mcs_procs AS (
  -- Mechanical circulatory support procedures (ECMO, IABP, VAD, etc.)
  SELECT p.subject_id, p.hadm_id, p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
    ON p.icd_code = d.icd_code
   AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%ecmo%'
     OR LOWER(d.long_title) LIKE '%intra-aortic balloon%'
     OR LOWER(d.long_title) LIKE '%ventricular assist%'
     OR LOWER(d.long_title) LIKE '%iabp%'
     OR LOWER(d.long_title) LIKE '%extracorporeal%'
  AND p.subject_id IN (SELECT subject_id FROM eligible)
)
SELECT MIN(cnt) AS min_distinct_mcs_procedures
FROM (
  SELECT subject_id, COUNT(DISTINCT icd_code) AS cnt
  FROM mcs_procs
  GROUP BY subject_id
) AS per_patient
WHERE cnt > 0;