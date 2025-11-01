WITH pneumonia_adms AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    USING (subject_id, hadm_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 79 AND 89
    AND di.seq_num = 1  -- principal diagnosis (pragmatic proxy for present-on-admission)
    AND (
      LOWER(dd.long_title) LIKE '%pneumonia%'
      OR LOWER(dd.long_title) LIKE '%aspiration%'
    )
    -- attempt to exclude obvious inter-facility transfers to approximate community-acquired
    AND (a.admission_location IS NULL OR UPPER(a.admission_location) NOT LIKE '%TRANSFER%')
    AND (a.admission_type IS NULL OR UPPER(a.admission_type) NOT LIKE '%TRANSFER%')
    -- require discharge time to compute LOS and in-hospital mortality reliably
    AND a.dischtime IS NOT NULL
),

hadm_flags AS (
  SELECT
    pa.*,
    -- hospital LOS in days (integer)
    TIMESTAMP_DIFF(pa.dischtime, pa.admittime, DAY) AS los_days,
    -- LOS group
    CASE WHEN TIMESTAMP_DIFF(pa.dischtime, pa.admittime, DAY) <= 7 THEN '<=7' ELSE '>7' END AS los_group,
    -- day-1 ICU: any icu stay with intime within first 24 hours of admission
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` s
      WHERE s.hadm_id = pa.hadm_id
        AND s.intime < TIMESTAMP_ADD(pa.admittime, INTERVAL 1 DAY)
    ) AS day1_icu,
    -- mechanical ventilation via coded procedures
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
        ON p.icd_code = dp.icd_code
       AND p.icd_version = dp.icd_version
      WHERE p.hadm_id = pa.hadm_id
        AND (
          LOWER(dp.long_title) LIKE '%ventilat%'   -- catches "ventilation" / "ventilator"
          OR LOWER(dp.long_title) LIKE '%intubat%' -- catches "intubation"
        )
    ) AS mechvent,
    -- renal replacement therapy via coded procedures (dialysis / hemofiltration / CRRT)
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
        ON p.icd_code = dp.icd_code
       AND p.icd_version = dp.icd_version
      WHERE p.hadm_id = pa.hadm_id
        AND (
          LOWER(dp.long_title) LIKE '%dialysis%'
          OR LOWER(dp.long_title) LIKE '%hemodialysis%'
          OR LOWER(dp.long_title) LIKE '%renal replacement%'
          OR LOWER(dp.long_title) LIKE '%hemofil%'
          OR LOWER(dp.long_title) LIKE '%continuous renal%'
        )
    ) AS rrt,
    -- vasopressor exposure from prescriptions or pharmacy orders during the admission
    (
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        WHERE pr.hadm_id = pa.hadm_id
          AND pr.starttime IS NOT NULL
          AND pr.starttime BETWEEN pa.admittime AND pa.dischtime
          AND (
            LOWER(pr.drug) LIKE '%norepinephrine%'
            OR LOWER(pr.drug) LIKE '%levophed%'
            OR LOWER(pr.drug) LIKE '%epinephrine%'
            OR LOWER(pr.drug) LIKE '%adrenaline%'
            OR LOWER(pr.drug) LIKE '%vasopressin%'
            OR LOWER(pr.drug) LIKE '%phenylephrine%'
            OR LOWER(pr.drug) LIKE '%dopamine%'
            OR LOWER(pr.drug) LIKE '%dobutamine%'
          )
      )
      OR
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
        WHERE ph.hadm_id = pa.hadm_id
          AND ph.starttime IS NOT NULL
          AND ph.starttime BETWEEN pa.admittime AND pa.dischtime
          AND (
            LOWER(ph.medication) LIKE '%norepinephrine%'
            OR LOWER(ph.medication) LIKE '%levophed%'
            OR LOWER(ph.medication) LIKE '%epinephrine%'
            OR LOWER(ph.medication) LIKE '%adrenaline%'
            OR LOWER(ph.medication) LIKE '%vasopressin%'
            OR LOWER(ph.medication) LIKE '%phenylephrine%'
            OR LOWER(ph.medication) LIKE '%dopamine%'
            OR LOWER(ph.medication) LIKE '%dobutamine%'
          )
      )
    ) AS vasopressor
  FROM pneumonia_adms pa
)

SELECT
  los_group,
  CASE WHEN day1_icu THEN 'Day1-ICU: Yes' ELSE 'Day1-ICU: No' END AS day1_icu,
  COUNT(*) AS n_admissions,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)), 1) AS mortality_pct,
  SUM(CASE WHEN mechvent THEN 1 ELSE 0 END) AS mechvent_n,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN mechvent THEN 1 ELSE 0 END), COUNT(*)), 1) AS mechvent_pct,
  SUM(CASE WHEN vasopressor THEN 1 ELSE 0 END) AS vasopressor_n,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN vasopressor THEN 1 ELSE 0 END), COUNT(*)), 1) AS vasopressor_pct,
  SUM(CASE WHEN rrt THEN 1 ELSE 0 END) AS rrt_n,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN rrt THEN 1 ELSE 0 END), COUNT(*)), 1) AS rrt_pct
FROM hadm_flags
GROUP BY los_group, day1_icu
ORDER BY
  -- order by LOS then ICU status
  CASE WHEN los_group = '<=7' THEN 0 ELSE 1 END,
  day1_icu;