WITH patients_filtered AS (
  SELECT 
    p.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 90 AND 100
),
first_icu_stay AS (
  SELECT 
    i.hadm_id,
    i.los
  FROM (
    SELECT 
      *,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS stay_rank
    FROM `physionet-data.mimiciv_3_1_icu`.icustays
  ) i
  WHERE i.stay_rank = 1
    AND i.los >= 1 
    AND i.los <= 7
),
imaging_counts AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp`.hcpcsevents h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_hcpcs d
    ON h.hcpcs_cd = d.code
  WHERE d.category = 2
  GROUP BY h.hadm_id
),
admissions_with_imaging AS (
  SELECT 
    f.hadm_id,
    f.los,
    COALESCE(i.imaging_count, 0) AS imaging_count
  FROM first_icu_stay f
  INNER JOIN patients_filtered p 
    ON f.hadm_id = p.hadm_id
  LEFT JOIN imaging_counts i 
    ON f.hadm_id = i.hadm_id
)
SELECT 
  CASE 
    WHEN los BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los BETWEEN 4 AND 7 THEN '4-7 days'
  END AS stay_group,
  AVG(imaging_count) AS mean_imaging,
  MIN(imaging_count) AS min_imaging,
  MAX(imaging_count) AS max_imaging
FROM admissions_with_imaging
GROUP BY stay_group
ORDER BY stay_group;