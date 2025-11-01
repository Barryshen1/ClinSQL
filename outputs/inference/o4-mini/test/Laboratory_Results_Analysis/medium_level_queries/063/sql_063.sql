WITH acs_admissions AS (
  -- Admissions with an ACS diagnosis
  SELECT DISTINCT d.subject_id,
                  d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%acute%'
    AND LOWER(dd.long_title) LIKE '%coronary%'
),
eligible_patients AS (
  -- Female patients aged 84-94 with ACS admissions
  SELECT p.subject_id,
         a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN acs_admissions acs
    ON a.subject_id = acs.subject_id
   AND a.hadm_id    = acs.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
),
first_troponin AS (
  -- First Troponin I per admission
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum,
    le.ref_range_upper,
    ROW_NUMBER() OVER (
      PARTITION BY le.subject_id, le.hadm_id
      ORDER BY le.charttime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE LOWER(li.label) LIKE '%troponin i%'
    AND le.valuenum IS NOT NULL
),
filtered AS (
  -- Only the first elevated Troponin I per eligible admission
  SELECT ft.valuenum
  FROM first_troponin ft
  JOIN eligible_patients ep
    ON ft.subject_id = ep.subject_id
   AND ft.hadm_id   = ep.hadm_id
  WHERE ft.rn = 1
    AND ft.valuenum > ft.ref_range_upper  -- exceeds ULN
)
SELECT
  (SELECT COUNT(*)         FROM filtered) AS n_admissions,
  (SELECT AVG(valuenum)    FROM filtered) AS mean_troponin,
  q.quartiles[OFFSET(1)]                   AS q1_troponin,
  q.quartiles[OFFSET(2)]                   AS median_troponin,
  q.quartiles[OFFSET(3)]                   AS q3_troponin,
  q.quartiles[OFFSET(3)] - q.quartiles[OFFSET(1)] AS iqr_troponin
FROM (
  SELECT APPROX_QUANTILES(valuenum, 4) AS quartiles
  FROM filtered
) AS q;