SELECT MIN(l.valuenum) AS min_troponin
FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
INNER JOIN (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON d.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (
      (d.icd_version = 10 AND 
         (d.icd_code = 'I200' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
      OR
      (d.icd_version = 9 AND 
         (d.icd_code LIKE '410%' OR d.icd_code = '4111'))
    )
) acs ON l.hadm_id = acs.hadm_id
WHERE l.itemid IN (51003, 51006)  -- Troponin T and I
  AND l.valueuom = 'ng/mL';       -- Ensure consistent units;