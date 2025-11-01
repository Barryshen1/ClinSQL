WITH eligible_patients AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    p.gender, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%')
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'I50%'
    )
),

time_windows AS (
  SELECT 
    ep.subject_id,
    ep.hadm_id,
    ep.admittime,
    COALESCE(ep.deathtime, ep.dischtime) AS end_time,
    ep.admittime AS first_start,
    ep.admittime + INTERVAL '24' HOUR AS first_end,
    COALESCE(ep.deathtime, ep.dischtime) - INTERVAL '24' HOUR AS final_start,
    COALESCE(ep.deathtime, ep.dischtime) AS final_end
  FROM eligible_patients ep
),

prescriptions_in_window AS (
  SELECT 
    tw.hadm_id,
    tw.first_start,
    tw.first_end,
    tw.final_start,
    tw.final_end,
    p.starttime,
    CASE 
      WHEN LOWER(p.drug) LIKE '%insulin%' AND (p.route = 'subcutaneous' OR p.route = 'intravenous') THEN 'insulin'
      WHEN p.route = 'oral' THEN 'oral'
      ELSE NULL
    END AS drug_category
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN time_windows tw 
    ON p.hadm_id = tw.hadm_id
  WHERE p.starttime IS NOT NULL
    AND (
      p.starttime BETWEEN tw.first_start AND tw.first_end
      OR p.starttime BETWEEN tw.final_start AND tw.final_end
    )
),

aggregated AS (
  SELECT 
    tw.hadm_id,
    MAX(CASE WHEN p.starttime BETWEEN tw.first_start AND tw.first_end AND p.drug_category = 'insulin' THEN 1 ELSE 0 END) AS first_insulin,
    MAX(CASE WHEN p.starttime BETWEEN tw.first_start AND tw.first_end AND p.drug_category = 'oral' THEN 1 ELSE 0 END) AS first_oral,
    MAX(CASE WHEN p.starttime BETWEEN tw.final_start AND tw.final_end AND p.drug_category = 'insulin' THEN 1 ELSE 0 END) AS final_insulin,
    MAX(CASE WHEN p.starttime BETWEEN tw.final_start AND tw.final_end AND p.drug_category = 'oral' THEN 1 ELSE 0 END) AS final_oral
  FROM time_windows tw
  LEFT JOIN prescriptions_in_window p 
    ON tw.hadm_id = p.hadm_id
  GROUP BY tw.hadm_id
)

SELECT 
  AVG(first_insulin) * 100 AS first_insulin_rate,
  AVG(first_oral) * 100 AS first_oral_rate,
  AVG(final_insulin) * 100 AS final_insulin_rate,
  AVG(final_oral) * 100 AS final_oral_rate,
  (AVG(first_insulin) - AVG(final_insulin)) * 100 AS insulin_diff,
  (AVG(first_oral) - AVG(final_oral)) * 100 AS oral_diff
FROM aggregated;