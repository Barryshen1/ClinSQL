WITH qualifying_procedures AS (
  SELECT DISTINCT p.hadm_id, p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON p.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 82 AND 92
    AND (LOWER(d.long_title) LIKE '%pacemaker%'
         OR LOWER(d.long_title) LIKE '%icd%'
         OR LOWER(d.long_title) LIKE '%cardioverter-defibrillator%'
         OR LOWER(d.long_title) LIKE '%implant%'
         OR LOWER(d.long_title) LIKE '%insertion%'
         OR LOWER(d.long_title) LIKE '%device%cardiac%')
    AND p.hadm_id IS NOT NULL
)
SELECT COALESCE(MIN(proc_count), 0) AS min_distinct_procedures_per_hospitalization
FROM (
  SELECT hadm_id, COUNT(DISTINCT icd_code) AS proc_count
  FROM qualifying_procedures
  GROUP BY hadm_id
  HAVING proc_count > 0
);