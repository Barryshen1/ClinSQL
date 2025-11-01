WITH acs_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE 
      WHEN di.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS diag_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON adm.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON adm.hadm_id = di.hadm_id
  -- ICD filter for ACS
  WHERE (
      (di.icd_version = 10 AND (
         di.icd_code LIKE 'I20%' OR di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' OR 
         di.icd_code LIKE 'I23%' OR di.icd_code LIKE 'I24%' OR di.icd_code LIKE 'I25%'
      ))
      OR (di.icd_version = 9 AND (
         di.icd_code BETWEEN '410' AND '41499'  -- ICD-9 equivalents of ACS
      ))
  )
  AND p.gender = 'F'
  AND p.anchor_age BETWEEN 77 AND 87
),
rad_ct_counts AS (
  SELECT
    la.hadm_id,
    COUNT(*) AS rad_ct_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS la
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON la.itemid = dli.itemid
  WHERE LOWER(dli.category) = 'radiology'
     OR LOWER(dli.label) LIKE '%ct%'
     OR LOWER(dli.label) LIKE '%xray%'
  GROUP BY la.hadm_id
),
combined AS (
  SELECT
    a.hadm_id,
    a.diag_type,
    CASE 
      WHEN a.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN a.los_days BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE NULL
    END AS los_group,
    IFNULL(r.rad_ct_count, 0) AS rad_ct_count
  FROM acs_admissions AS a
  LEFT JOIN rad_ct_counts AS r
    ON a.hadm_id = r.hadm_id
  WHERE a.los_days BETWEEN 1 AND 8
)
SELECT
  los_group,
  diag_type,
  AVG(rad_ct_count) AS mean_rad_ct,
  MIN(rad_ct_count) AS min_rad_ct,
  MAX(rad_ct_count) AS max_rad_ct
FROM combined
WHERE los_group IS NOT NULL
GROUP BY los_group, diag_type
ORDER BY los_group, diag_type;