WITH ace_prescriptions AS (
  SELECT
    p.subject_id,
    ps.starttime,
    ps.stoptime,
    TIMESTAMP_DIFF(ps.stoptime, ps.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` ps
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ps.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age = 55
    AND ps.hadm_id IS NOT NULL
    AND ps.starttime IS NOT NULL
    AND ps.stoptime IS NOT NULL
    AND LOWER(ps.drug) LIKE '%lisinopril%'
     OR LOWER(ps.drug) LIKE '%enalapril%'
     OR LOWER(ps.drug) LIKE '%ramipril%'
     OR LOWER(ps.drug) LIKE '%benazepril%'
     OR LOWER(ps.drug) LIKE '%captopril%'
     OR LOWER(ps.drug) LIKE '%perindopril%'
     OR LOWER(ps.drug) LIKE '%quinapril%'
     OR LOWER(ps.drug) LIKE '%moexipril%'
     OR LOWER(ps.drug) LIKE '%trandolapril%'
)
SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS percentile_25_days
FROM ace_prescriptions
WHERE duration_days > 0;