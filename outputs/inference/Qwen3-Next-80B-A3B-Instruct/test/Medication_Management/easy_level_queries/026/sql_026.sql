WITH dihydropyridine_ccb_drugs AS (
  SELECT UNNEST(ARRAY[
    'amlodipine',
    'nifedipine',
    'felodipine',
    'nicardipine',
    'nimodipine',
    'isradipine',
    'pranidipine',
    'lacidipine',
    'lercanidipine'
  ]) AS drug
),
filtered_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    DATETIME_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  INNER JOIN
    dihydropyridine_ccb_drugs d
    ON LOWER(p.drug) = LOWER(d.drug)
  WHERE
    pt.gender = 'F'
    AND pt.anchor_age BETWEEN 81 AND 91
    AND p.stoptime IS NOT NULL
    AND p.stoptime >= p.starttime
)
SELECT
  PERCENTILE_CONT(duration_days, 0.25) AS percentile_25_duration_days
FROM
  filtered_prescriptions;