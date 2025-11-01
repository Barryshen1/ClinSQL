WITH target_admissions AS (
  SELECT DISTINCT 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` e 
      ON a.subject_id = e.subject_id AND a.hadm_id = e.hadm_id
  WHERE 
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 81 AND 91
    AND (
      LOWER(e.medication) LIKE '%hydralazine%' 
      OR LOWER(e.medication) LIKE '%isosorbide dinitrate%'
    )
)
SELECT 
  MIN(DATE_DIFF(dischtime, admittime, DAY)) AS shortest_duration_days
FROM target_admissions;