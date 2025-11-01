WITH admissions_filtered AS (
  SELECT 
    a.hadm_id,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS admittime_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 77 AND 87
),
first_icu_stay AS (
  SELECT 
    hadm_id,
    stay_id
  FROM (
    SELECT 
      i.hadm_id,
      i.stay_id,
      ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN admissions_filtered af
      ON i.hadm_id = af.hadm_id
  ) AS t
  WHERE t.rn = 1
),
spo2_measurements AS (
  SELECT 
    c.stay_id,
    c.charttime,
    c.valuenum AS spo2_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  WHERE 
    (d.label LIKE '%SpO2%' OR d.label LIKE '%oxygen saturation%')
    AND c.valuenum IS NOT NULL
),
first_spo2_per_stay AS (
  SELECT 
    stay_id,
    spo2_value
  FROM (
    SELECT 
      stay_id,
      spo2_value,
      ROW_NUMBER() OVER (PARTITION BY stay_id ORDER BY charttime) AS rn
    FROM spo2_measurements
  ) 
  WHERE rn = 1
)
SELECT 
  STDDEV(spo2_value) AS std_spo2
FROM first_spo2_per_stay
INNER JOIN first_icu_stay 
  ON first_spo2_per_stay.stay_id = first_icu_stay.stay_id;