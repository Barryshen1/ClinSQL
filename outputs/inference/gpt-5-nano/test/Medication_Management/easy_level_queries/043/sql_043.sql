WITH base AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE LOWER(p.gender) IN ('f', 'female')
    AND a.dischtime IS NOT NULL
    -- age at admission based on anchor_age and anchor_year
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 81 AND 91
    -- the admission includes hydralazine or isosorbide dinitrate
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      WHERE pr.subject_id = a.subject_id
        AND pr.hadm_id = a.hadm_id
        AND (LOWER(pr.drug) LIKE '%hydralazine%' OR LOWER(pr.drug) LIKE '%isosorbide dinitrate%')
    )
)
SELECT MIN(DATE_DIFF(DATE(dischtime), DATE(admittime), DAY)) AS shortest_inpatient_duration_days
FROM base;