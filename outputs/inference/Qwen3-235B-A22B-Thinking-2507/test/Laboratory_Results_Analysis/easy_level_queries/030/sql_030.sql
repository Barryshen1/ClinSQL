SELECT MIN(l.valuenum) AS min_troponin
FROM `physionet-data.mimiciv_3_1_hosp`.patients p
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON p.subject_id = a.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.labevents l
  ON a.hadm_id = l.hadm_id
WHERE p.gender = 'M'
  AND l.itemid IN (50189, 50190, 50191, 50192)
  AND l.valuenum IS NOT NULL
  AND l.charttime >= a.admittime
  AND l.charttime <= a.dischtime
  AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
      WHERE d.hadm_id = a.hadm_id
        AND (d.icd_code = 'I200' OR d.icd_code = 'I240' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')
  );