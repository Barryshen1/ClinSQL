WITH
cohort AS (
  SELECT
    p.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON p.subject_id = adm.subject_id
  WHERE
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) + p.anchor_age BETWEEN 56 AND 66
    -- Filter for patients with a Diabetes diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      WHERE dx.hadm_id = adm.hadm_id
        AND (
          dx.icd_code LIKE '250%' -- ICD-9
          OR dx.icd_code LIKE 'E08%' -- ICD-10
          OR dx.icd_code LIKE 'E09%' -- ICD-10
          OR dx.icd_code LIKE 'E10%' -- ICD-10
          OR dx.icd_code LIKE 'E11%' -- ICD-10
          OR dx.icd_code LIKE 'E13%' -- ICD-10
        )
    )
    -- Filter for patients with a Heart Failure diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      WHERE dx.hadm_id = adm.hadm_id
        AND (
          dx.icd_code LIKE '428%' -- ICD-9
          OR dx.icd_code LIKE 'I50%' -- ICD-10
        )
    )
),

glp1_usage AS (
  SELECT
    c.hadm_id,
    MAX(CASE
      WHEN pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
      THEN 1
      ELSE 0
    END) AS used_in_first_48h,
    MAX(CASE
      WHEN pr.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
      THEN 1
      ELSE 0
    END) AS used_in_final_24h
  FROM cohort AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON c.hadm_id = pr.hadm_id
    -- Filter for GLP-1 receptor agonists in the JOIN condition
    AND (
      LOWER(pr.drug) LIKE '%semaglutide%' OR LOWER(pr.drug) LIKE '%ozempic%' OR LOWER(pr.drug) LIKE '%rybelsus%' OR LOWER(pr.drug) LIKE '%wegovy%'
      OR LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%victoza%' OR LOWER(pr.drug) LIKE '%saxenda%'
      OR LOWER(pr.drug) LIKE '%dulaglutide%' OR LOWER(pr.drug) LIKE '%trulicity%'
      OR LOWER(pr.drug) LIKE '%exenatide%' OR LOWER(pr.drug) LIKE '%byetta%' OR LOWER(pr.drug) LIKE '%bydureon%'
      OR LOWER(pr.drug) LIKE '%lixisenatide%' OR LOWER(pr.drug) LIKE '%adlyxin%'
    )
  GROUP BY
    c.hadm_id
),

stats AS (
  SELECT
    COUNT(hadm_id) AS total_patients,
    SUM(used_in_first_48h) AS patients_used_first_48h,
    SUM(used_in_final_24h) AS patients_used_final_24h
  FROM glp1_usage
)

SELECT
  s.total_patients,
  s.patients_used_first_48h,
  s.patients_used_final_24h,
  SAFE_DIVIDE(s.patients_used_first_48h, s.total_patients) * 100 AS prevalence_first_48h_pct,
  SAFE_DIVIDE(s.patients_used_final_24h, s.total_patients) * 100 AS prevalence_final_24h_pct,
  (SAFE_DIVIDE(s.patients_used_final_24h, s.total_patients) * 100) - (SAFE_DIVIDE(s.patients_used_first_48h, s.total_patients) * 100) AS net_change_pct
FROM stats AS s;