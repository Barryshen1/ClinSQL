SELECT COUNT(DISTINCT a.hadm_id) AS cohort_count
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON p.subject_id = a.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  ON di.subject_id = a.subject_id
  AND di.hadm_id = a.hadm_id
  AND di.seq_num = 1  -- principal diagnosis
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
  ON di.icd_code = ddi.icd_code
  AND di.icd_version = ddi.icd_version
WHERE
  -- Demographics: female
  UPPER(p.gender) = 'F'
  -- Medicare insurance
  AND (
        a.insurance LIKE '%Medicare%'
        OR a.insurance LIKE '%medicare%'
      )
  -- Age at admission (anchor-age method)
  AND p.anchor_age IS NOT NULL
  AND p.anchor_year IS NOT NULL
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 68 AND 78
  -- Admission from ED
  AND (
        UPPER(a.admission_type) = 'EMERGENCY'
        OR UPPER(a.admission_location) LIKE '%EMERGENCY%'
      )
  -- Hemorrhagic stroke (ICD-9/10) as principal diagnosis
  AND ddi.long_title LIKE '%hemorrh%'
  -- Documented discharge
  AND a.dischtime IS NOT NULL
  AND a.discharge_location IS NOT NULL;