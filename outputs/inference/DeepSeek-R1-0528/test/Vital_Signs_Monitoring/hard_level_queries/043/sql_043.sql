WITH cohort AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id, 
    i.intime, 
    i.outtime, 
    i.los AS icu_los,
    p.gender, 
    p.anchor_age,
    p.anchor_year,
    DATETIME_DIFF(i.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age AS age_at_icu_admit,
    a.hospital_expire_flag AS mortality
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE 
    p.gender = 'M'
    AND DATETIME_DIFF(i.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age BETWEEN 40 AND 50
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE i.hadm_id = d.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('51881','51882','51884','51885','51889','5189','7991'))
          OR
          (d.icd_version = 10 AND d.icd_code IN ('J9600','J9601','J9602','J9620','J9621','J9622','J9690','J9691','J9692','R092'))
        )
    )
),
hr_data AS (
  SELECT 
    c.stay_id,
    ce.valuenum AS hr,
    ABS(ce.valuenum - 80) AS hr_abs_dev
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (211, 220045) 
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum BETWEEN 20 AND 250
),
hr_agg AS (
  SELECT 
    stay_id,
    AVG(hr_abs_dev) AS avg_hr_abs_dev,
    COUNT(*) AS hr_count,
    SUM(CASE WHEN hr > 100 THEN 1 ELSE 0 END) AS tachycardic_count
  FROM hr_data
  GROUP BY stay_id
),
map_data AS (
  SELECT 
    c.stay_id,
    ce.valuenum AS map,
    ABS(ce.valuenum - 90) AS map_abs_dev
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (456,52,6702,443,220052,220181,225312)
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum BETWEEN 20 AND 200
),
map_agg AS (
  SELECT 
    stay_id,
    AVG(map_abs_dev) AS avg_map_abs_dev,
    COUNT(*) AS map_count,
    SUM(CASE WHEN map < 65 THEN 1 ELSE 0 END) AS hypotensive_count
  FROM map_data
  GROUP BY stay_id
),
rr_data AS (
  SELECT 
    c.stay_id,
    ce.valuenum AS rr,
    ABS(ce.valuenum - 20) AS rr_abs_dev
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (618,220210,224690)
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum BETWEEN 5 AND 100
),
rr_agg AS (
  SELECT 
    stay_id,
    AVG(rr_abs_dev) AS avg_rr_abs_dev,
    COUNT(*) AS rr_count
  FROM rr_data
  GROUP BY stay_id
),
temp_data AS (
  SELECT 
    c.stay_id,
    CASE 
      WHEN ce.itemid IN (223761,678,679,3652,3654) THEN (ce.valuenum - 32) / 1.8
      ELSE ce.valuenum
    END AS temp_c,
    ABS(
      CASE 
        WHEN ce.itemid IN (223761,678,679,3652,3654) THEN (ce.valuenum - 32) / 1.8
        ELSE ce.valuenum
      END - 37
    ) AS temp_abs_dev
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (223761,223762,676,677,678,679,3652,3654)
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND (
      (ce.itemid IN (223761,678,679,3652,3654) AND ce.valuenum BETWEEN 77 AND 113) 
      OR 
      (ce.itemid NOT IN (223761,678,679,3652,3654) AND ce.valuenum BETWEEN 25 AND 45)
    )
),
temp_agg AS (
  SELECT 
    stay_id,
    AVG(temp_abs_dev) AS avg_temp_abs_dev,
    COUNT(*) AS temp_count
  FROM temp_data
  GROUP BY stay_id
),
spo2_data AS (
  SELECT 
    c.stay_id,
    ce.valuenum AS spo2,
    ABS(ce.valuenum - 95) AS spo2_abs_dev
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (646,220277)
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum BETWEEN 0 AND 100
),
spo2_agg AS (
  SELECT 
    stay_id,
    AVG(spo2_abs_dev) AS avg_spo2_abs_dev,
    COUNT(*) AS spo2_count
  FROM spo2_data
  GROUP BY stay_id
),
agg AS (
  SELECT 
    c.stay_id,
    c.icu_los,
    c.mortality,
    (hr.avg_hr_abs_dev / 20) + 
    (map.avg_map_abs_dev / 10) + 
    (rr.avg_rr_abs_dev / 5) + 
    (temp.avg_temp_abs_dev) + 
    (spo2.avg_spo2_abs_dev / 5) AS vii,
    map.hypotensive_count / map.map_count AS hypotensive_burden,
    hr.tachycardic_count / hr.hr_count AS tachycardic_burden,
    CASE WHEN map.hypotensive_count > 0 THEN 1 ELSE 0 END AS hypotensive_ever,
    CASE WHEN hr.tachycardic_count > 0 THEN 1 ELSE 0 END AS tachycardic_ever
  FROM cohort c
  INNER JOIN hr_agg hr ON c.stay_id = hr.stay_id
  INNER JOIN map_agg map ON c.stay_id = map.stay_id
  INNER JOIN rr_agg rr ON c.stay_id = rr.stay_id
  INNER JOIN temp_agg temp ON c.stay_id = temp.stay_id
  INNER JOIN spo2_agg spo2 ON c.stay_id = spo2.stay_id
)
SELECT 
  group_name,
  COUNT(*) AS n_patients,
  STDDEV(vii) AS vii_stddev,
  APPROX_QUANTILES(vii, 100)[OFFSET(25)] AS vii_25p,
  APPROX_QUANTILES(vii, 100)[OFFSET(50)] AS vii_50p,
  APPROX_QUANTILES(vii, 100)[OFFSET(75)] AS vii_75p,
  APPROX_QUANTILES(vii, 100)[OFFSET(95)] AS vii_95p,
  AVG(hypotensive_burden) AS avg_hypotensive_burden,
  AVG(tachycardic_burden) AS avg_tachycardic_burden,
  AVG(icu_los) AS avg_icu_los,
  AVG(mortality) AS mortality_rate
FROM (
  SELECT 
    'Entire group' AS group_name,
    *
  FROM agg
  UNION ALL
  SELECT 
    'Hypotensive subgroup' AS group_name,
    *
  FROM agg
  WHERE hypotensive_ever = 1
  UNION ALL
  SELECT 
    'Tachycardic subgroup' AS group_name,
    *
  FROM agg
  WHERE tachycardic_ever = 1
)
GROUP BY group_name
ORDER BY group_name;