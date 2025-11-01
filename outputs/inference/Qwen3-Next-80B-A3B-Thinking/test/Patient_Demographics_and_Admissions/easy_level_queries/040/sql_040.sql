SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS median_los
FROM (
  SELECT i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 35 AND 45
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = i.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '438')
          OR (d.icd_version = 10 AND d.icd_code BETWEEN 'I60' AND 'I69')
        )
    )
) subquery;