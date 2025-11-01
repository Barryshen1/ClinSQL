WITH patients_filtered AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
),
aspirin_pres AS (
  SELECT 
    pr.hadm_id, 
    pr.starttime, 
    pr.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN patients_filtered pf 
    ON pr.subject_id = pf.subject_id 
    AND pr.hadm_id = pf.hadm_id
  WHERE LOWER(pr.drug) LIKE '%aspirin%'
    AND pr.starttime >= pf.admittime
),
p2y12_pres AS (
  SELECT 
    pr.hadm_id, 
    pr.starttime, 
    pr.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN patients_filtered pf 
    ON pr.subject_id = pf.subject_id 
    AND pr.hadm_id = pf.hadm_id
  WHERE (LOWER(pr.drug) LIKE '%clopidogrel%' 
         OR LOWER(pr.drug) LIKE '%prasugrel%' 
         OR LOWER(pr.drug) LIKE '%ticagrelor%')
    AND pr.starttime >= pf.admittime
),
hadm_with_aspirin AS (
  SELECT DISTINCT hadm_id 
  FROM aspirin_pres
),
hadm_with_p2y12 AS (
  SELECT DISTINCT hadm_id 
  FROM p2y12_pres
),
qualifying_hadm AS (
  SELECT ha.hadm_id
  FROM hadm_with_aspirin ha
  INNER JOIN hadm_with_p2y12 hp 
    ON ha.hadm_id = hp.hadm_id
),
aspirin_summary AS (
  SELECT 
    ap.hadm_id, 
    MIN(ap.starttime) AS asp_min_start,
    MAX(COALESCE(ap.stoptime, pf.dischtime)) AS asp_max_stop
  FROM aspirin_pres ap
  INNER JOIN patients_filtered pf 
    ON ap.hadm_id = pf.hadm_id
  GROUP BY ap.hadm_id, pf.dischtime
),
p2y12_summary AS (
  SELECT 
    pp.hadm_id, 
    MIN(pp.starttime) AS p2_min_start,
    MAX(COALESCE(pp.stoptime, pf.dischtime)) AS p2_max_stop
  FROM p2y12_pres pp
  INNER JOIN patients_filtered pf 
    ON pp.hadm_id = pf.hadm_id
  GROUP BY pp.hadm_id, pf.dischtime
),
qualifying_durations AS (
  SELECT 
    DATE_DIFF(
      LEAST(asp.asp_max_stop, p2.p2_max_stop), 
      GREATEST(asp.asp_min_start, p2.p2_min_start), 
      DAY
    ) + 1 AS duration
  FROM qualifying_hadm q
  INNER JOIN aspirin_summary asp 
    ON q.hadm_id = asp.hadm_id
  INNER JOIN p2y12_summary p2 
    ON q.hadm_id = p2.hadm_id
  WHERE GREATEST(asp.asp_min_start, p2.p2_min_start) < LEAST(asp.asp_max_stop, p2.p2_max_stop)
)
SELECT 
  AVG(duration) AS median_duration_days
FROM (
  SELECT 
    duration,
    ROW_NUMBER() OVER (ORDER BY duration) AS rn,
    COUNT(*) OVER() AS total_count
  FROM qualifying_durations
) ranked
WHERE rn IN (FLOOR((total_count + 1)/2), CEIL((total_count + 1)/2));