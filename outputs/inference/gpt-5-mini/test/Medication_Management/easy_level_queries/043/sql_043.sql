WITH med_admissions AS (
  -- prescriptions
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(COALESCE(drug, '')) LIKE '%hydralazine%'
     OR (LOWER(COALESCE(drug, '')) LIKE '%isosorbide%' AND LOWER(COALESCE(drug, '')) LIKE '%dinitrate%')

  UNION DISTINCT

  -- pharmacy
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE LOWER(COALESCE(medication, '')) LIKE '%hydralazine%'
     OR (LOWER(COALESCE(medication, '')) LIKE '%isosorbide%' AND LOWER(COALESCE(medication, '')) LIKE '%dinitrate%')

  UNION DISTINCT

  -- emar (electronic medication administration records)
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE LOWER(COALESCE(medication, '')) LIKE '%hydralazine%'
     OR (LOWER(COALESCE(medication, '')) LIKE '%isosorbide%' AND LOWER(COALESCE(medication, '')) LIKE '%dinitrate%')
),

qualified_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN med_admissions m USING (hadm_id)
  WHERE a.dischtime IS NOT NULL
)

SELECT
  ROUND(MIN(qa.duration_days), 2) AS shortest_duration_days
FROM qualified_admissions qa
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON qa.subject_id = p.subject_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 81 AND 91;