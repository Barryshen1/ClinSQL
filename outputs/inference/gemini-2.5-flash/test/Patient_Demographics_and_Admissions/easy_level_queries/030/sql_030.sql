SELECT
  STDDEV(fad.los_days) AS std_dev_los_days
FROM (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp`.admissions AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.patients AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND a.dischtime IS NOT NULL -- Ensure a valid discharge time for LOS calculation
) AS fad
INNER JOIN (
  SELECT DISTINCT
    pr.subject_id,
    pr.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp`.prescriptions AS pr
  WHERE
    LOWER(pr.drug) LIKE '%heparin%' OR
    LOWER(pr.drug) LIKE '%warfarin%' OR
    LOWER(pr.drug) LIKE '%rivaroxaban%' OR
    LOWER(pr.drug) LIKE '%apixaban%' OR
    LOWER(pr.drug) LIKE '%dabigatran%' OR
    LOWER(pr.drug) LIKE '%enoxaparin%'
) AS aa
  ON fad.subject_id = aa.subject_id AND fad.hadm_id = aa.hadm_id
WHERE
  fad.rn = 1 -- Select only the first admission for each patient
  AND fad.age_at_admission BETWEEN 52 AND 62;