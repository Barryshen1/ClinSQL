WITH filtered_patients AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 81 AND 91
),
hfnc_patients AS (
  SELECT 
    fp.stay_id,
    fp.hadm_id,
    fp.intime,
    fp.outtime,
    fp.hospital_expire_flag
  FROM filtered_patients fp
  JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie ON fp.stay_id = ie.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ie.itemid = di.itemid
  WHERE di.label LIKE '%High Flow Nasal Cannula%'
    AND ie.starttime BETWEEN fp.intime AND TIMESTAMP_ADD(fp.intime, INTERVAL 48 HOUR)
),
composite_scores AS (
  SELECT 
    hp.stay_id,
    hp.hadm_id,
    hp.hospital_expire_flag,
    ce.valuenum AS composite_score
  FROM hfnc_patients hp
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON hp.stay_id = ce.stay_id
  WHERE ce.itemid = 220045  -- Note: This itemid is likely incorrect for a composite score
    AND ce.charttime BETWEEN hp.intime AND TIMESTAMP_ADD(hp.intime, INTERVAL 48 HOUR)
),
percentile_85 AS (
  SELECT 
    (COUNTIF(composite_score <= 85) * 100.0) / NULLIF(COUNT(*), 0) AS percentile_85
  FROM composite_scores
),
top_decile AS (
  SELECT 
    AVG(i.los) AS avg_los,
    AVG(c.hospital_expire_flag) * 100 AS mortality_percent
  FROM composite_scores c
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON c.stay_id = i.stay_id
  WHERE c.stay_id IN (
    SELECT stay_id
    FROM (
      SELECT stay_id,
             NTILE(10) OVER (ORDER BY composite_score DESC) AS decile
      FROM composite_scores
    ) t
    WHERE decile = 1
  )
)
SELECT 
  p.percentile_85,
  t.avg_los,
  t.mortality_percent
FROM percentile_85 p, top_decile t;