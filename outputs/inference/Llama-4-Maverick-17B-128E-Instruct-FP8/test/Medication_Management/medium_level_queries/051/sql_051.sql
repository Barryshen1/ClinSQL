WITH cohort AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 86 AND 96
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code IN ('250', '428') OR icd_code LIKE '250%' OR icd_code LIKE '428%' 
  )
),
meds AS (
  SELECT c.subject_id, c.hadm_id, e.charttime, 
         CASE 
           WHEN e.medication LIKE '%insulin%' THEN 'Insulin'
           WHEN e.medication NOT LIKE '%insulin%' AND (e.medication LIKE '%metformin%' OR e.medication LIKE '%glipizide%') THEN 'Oral Agents'
           ELSE 'Other'
         END AS med_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` e ON c.hadm_id = e.hadm_id
  WHERE e.charttime IS NOT NULL
),
stay_times AS (
  SELECT c.subject_id, c.hadm_id, 
         MIN(a.admittime) AS admit_time, 
         MAX(a.dischtime) AS discharge_time
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
  GROUP BY c.subject_id, c.hadm_id
),
med_analysis AS (
  SELECT m.subject_id, m.hadm_id, m.med_class,
         CASE 
           WHEN m.charttime BETWEEN s.admit_time AND (s.admit_time + INTERVAL 12 HOUR) THEN 'Early'
           WHEN m.charttime BETWEEN (s.discharge_time - INTERVAL 72 HOUR) AND s.discharge_time THEN 'Late'
           ELSE 'Other'
         END AS timing
  FROM meds m
  INNER JOIN stay_times s ON m.hadm_id = s.hadm_id
  WHERE m.charttime BETWEEN s.admit_time AND s.discharge_time
)

SELECT med_class, timing, COUNT(DISTINCT hadm_id) AS num_hadm,
       COUNT(DISTINCT hadm_id) * 1.0 / (SELECT COUNT(DISTINCT hadm_id) FROM cohort) AS rate
FROM med_analysis
WHERE timing IN ('Early', 'Late')
GROUP BY med_class, timing

UNION ALL

SELECT 'Transition' AS med_class, 
       CONCAT(early.med_class, '->', late.med_class) AS timing,
       COUNT(DISTINCT early.hadm_id) AS num_hadm,
       COUNT(DISTINCT early.hadm_id) * 1.0 / (SELECT COUNT(DISTINCT hadm_id) FROM cohort) AS rate
FROM med_analysis early
INNER JOIN med_analysis late ON early.hadm_id = late.hadm_id
WHERE early.timing = 'Early' AND late.timing = 'Late'
GROUP BY early.med_class, late.med_class;