SELECT COUNT(DISTINCT a.hadm_id) AS index_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON p.subject_id = a.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  ON di.subject_id = a.subject_id
  AND di.hadm_id = a.hadm_id
  AND di.seq_num = 1
WHERE
  LOWER(p.gender) = 'f'
  AND LOWER(a.insurance) LIKE '%medicare%'
  AND (CAST(p.anchor_age AS FLOAT64) + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 46 AND 56
  AND (di.icd_code LIKE '820%' OR di.icd_code LIKE 'S72%')
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.transfers` AS t
    WHERE t.subject_id = a.subject_id
      AND t.hadm_id = a.hadm_id
      AND UPPER(t.eventtype) LIKE '%TRANSFER%'
  );