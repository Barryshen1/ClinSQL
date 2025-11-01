WITH pci_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE -- ICD-9 PCI codes
        (icd_version = 9 AND (
           icd_code = '0066' OR icd_code LIKE '360%' OR icd_code IN ('3606','3607')
        ))
        -- ICD-10 PCI codes (027...)
        OR (icd_version = 10 AND icd_code LIKE '027%')
),
pci_procs AS (
  SELECT p.subject_id, pr.hadm_id, pr.icd_code, pr.icd_version, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  JOIN pci_codes c
    ON pr.icd_code = c.icd_code AND pr.icd_version = c.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pr.subject_id = a.subject_id AND pr.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pr.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),
first_pci AS (
  SELECT subject_id, hadm_id, admittime, dischtime,
         ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM pci_procs
),
cohort AS (
  SELECT subject_id, hadm_id, admittime, dischtime
  FROM first_pci
  WHERE rn = 1
),
readmissions AS (
  SELECT c.subject_id, c.hadm_id AS index_hadm_id,
         COUNT(*) AS num_readmits
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON c.subject_id = a2.subject_id
   AND a2.admittime > c.dischtime
   AND a2.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
  GROUP BY c.subject_id, c.hadm_id
),
cohort_with_flag AS (
  SELECT c.subject_id,
         CASE WHEN r.num_readmits > 0 THEN 1 ELSE 0 END AS readmit_flag
  FROM cohort c
  LEFT JOIN readmissions r
    ON c.subject_id = r.subject_id
)
SELECT
  COUNTIF(readmit_flag = 1) / COUNT(*) AS avg_30day_readmit_rate
FROM cohort_with_flag;