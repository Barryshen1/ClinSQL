WITH eligible_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE d.seq_num = 1
    AND (
      -- ICD-9 ESRD: 585.6 or 5856
      (d.icd_version = 9 AND (d.icd_code IN ('585.6', '5856')))
      -- ICD-10 ESRD: N18.6
      OR (d.icd_version = 10 AND d.icd_code = 'N18.6')
    )
    -- Transfer from another hospital (broader capture)
    AND UPPER(a.admission_type) LIKE '%TRANSFER%'
    -- Medicare insured
    AND UPPER(a.insurance) LIKE '%MEDICARE%'
    -- Male
    AND UPPER(p.gender) IN ('M', 'MALE')
    -- Age at admission between 90 and 100
    AND p.anchor_age IS NOT NULL
    AND p.anchor_year IS NOT NULL
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 90 AND 100
)

SELECT COUNT(*) AS admissions_count
FROM eligible_admissions;