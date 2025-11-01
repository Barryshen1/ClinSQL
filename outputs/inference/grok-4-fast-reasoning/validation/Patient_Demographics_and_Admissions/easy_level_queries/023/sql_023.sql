WITH pci_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE (icd_version = 9 
         AND icd_code IN ('00.66', '36.00', '36.01', '36.02', '36.03', '36.05', '36.06', '36.07', '36.09'))
     OR (icd_version = 10 AND icd_code LIKE '027%')
)
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS median_icu_los_days
FROM `physionet-data.mimiciv_3_1_icu.icustays` i
INNER JOIN pci_hadms p ON i.hadm_id = p.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat ON i.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON i.hadm_id = adm.hadm_id
WHERE pat.gender = 'M'
  AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 68 AND 78;