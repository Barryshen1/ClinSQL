WITH sepsis_admissions AS (
  -- Get admissions for male patients age 50-60 with sepsis (no septic shock)
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    -- Sepsis diagnosis
    JOIN (
      SELECT
        hadm_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE
        (
          -- ICD-10 sepsis codes
          (d.icd_version = 10 AND (
            REGEXP_CONTAINS(icd_code, r'^A40') OR
            REGEXP_CONTAINS(icd_code, r'^A41') OR
            icd_code = 'R652'
          ))
          OR
          -- ICD-9 sepsis codes
          (d.icd_version = 9 AND (
            icd_code = '99591' OR
            icd_code = '99592'
          ))
        )
        -- Exclude septic shock
        AND hadm_id NOT IN (
          SELECT hadm_id
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
          WHERE
            (icd_version = 10 AND icd_code = 'R6521') -- Septic shock ICD-10
            OR (icd_version = 9 AND icd_code = '78552') -- Septic shock ICD-9
        )
      GROUP BY hadm_id
    ) sepsis
      ON a.hadm_id = sepsis.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
),

first_icu_stays AS (
  -- Get first ICU stay per admission
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    ROW_NUMBER() OVER (PARTITION BY s.hadm_id ORDER BY s.intime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
)
,
cohort AS (
  -- Join sepsis admissions to first ICU stay
  SELECT
    sa.subject_id,
    sa.hadm_id,
    sa.anchor_age,
    sa.gender,
    sa.hospital_expire_flag,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM
    sepsis_admissions sa
    JOIN first_icu_stays icu
      ON sa.hadm_id = icu.hadm_id
  WHERE
    icu.rn = 1
)
,
vent_itemids AS (
  -- Get itemids for mechanical ventilation from d_items
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%ventilat%'
     OR LOWER(label) LIKE '%mech%'
     OR LOWER(label) LIKE '%respirator%'
)
,
vent_status AS (
  -- For each ICU stay, check if patient was ventilated in first 24h
  SELECT
    c.stay_id,
    MAX(
      CASE WHEN ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
           THEN 1 ELSE 0 END
    ) AS ventilated_day1
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON c.stay_id = ce.stay_id
    JOIN vent_itemids vi
      ON ce.itemid = vi.itemid
  WHERE
    ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY c.stay_id
)
,
final_cohort AS (
  SELECT
    c.*,
    IFNULL(vs.ventilated_day1, 0) AS ventilated_day1,
    CASE WHEN c.los <= 7 THEN '<=7' ELSE '>7' END AS los_group
  FROM
    cohort c
    LEFT JOIN vent_status vs
      ON c.stay_id = vs.stay_id
)
SELECT
  los_group,
  ventilated_day1,
  COUNT(*) AS n_patients,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_percent,
  ROUND(APPROX_QUANTILES(los, 2)[OFFSET(1)], 2) AS median_los
FROM
  final_cohort
GROUP BY
  los_group,
  ventilated_day1
ORDER BY
  los_group,
  ventilated_day1 DESC;