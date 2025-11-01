WITH map_data AS (
  SELECT 
    stay.stay_id,
    AVG(ce.valuenum) AS avg_map
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` stay
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON stay.stay_id = ce.stay_id
    AND ce.itemid IN (220052, 52)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum <= 200
    AND ce.charttime BETWEEN stay.intime AND stay.outtime
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON stay.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND stay.first_careunit NOT LIKE '%Nursery%'
    AND (
      -- Deceased before/during stay: age at death
      (p.dod IS NOT NULL 
       AND p.dod <= stay.intime
       AND DATE_DIFF(p.dod, DATE(p.anchor_year - p.anchor_age, 1, 1), DAY) / 365.25 BETWEEN 38 AND 48)
      OR
      -- Alive at admission: age at admission
      (p.dod IS NULL OR p.dod > stay.intime
       AND EXTRACT(YEAR FROM stay.intime) - p.anchor_age BETWEEN 38 AND 48)
    )
  GROUP BY 
    stay.stay_id
  HAVING 
    COUNT(ce.valuenum) >= 1  -- Ensure at least one valid MAP per stay
),
total_stays AS (
  SELECT COUNT(*) AS total
  FROM map_data
),
low_map_stays AS (
  SELECT COUNT(*) AS low_count
  FROM map_data
  WHERE avg_map <= 60
)
SELECT 
  low_count * 1.0 / total AS percentile_rank
FROM 
  low_map_stays, total_stays;