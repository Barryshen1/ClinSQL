WITH ace_drugs AS (
  SELECT LOWER(drug_name) AS drug_name
  FROM UNNEST([
    'lisinopril', 'enalapril', 'captopril', 'ramipril', 'benazepril',
    'quinapril', 'perindopril', 'fosinopril', 'trandolapril', 'moexipril',
    'enalaprilat'
  ]) AS drug_name
),
ace_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.subject_id = pr.subject_id AND a.hadm_id = pr.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = pr.subject_id
  JOIN ace_drugs AS ad
    ON LOWER(pr.drug) LIKE CONCAT('%', ad.drug_name, '%')
  WHERE LOWER(p.gender) = 'f'
    -- age at admission: anchor_age + (admit_year - anchor_year)
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 38 AND 48
    AND pr.stoptime IS NOT NULL
    AND pr.starttime IS NOT NULL
)
SELECT
  CAST(MAX(duration_days) AS INT64) AS longest_ace_duration_days
FROM ace_prescriptions;