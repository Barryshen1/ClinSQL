WITH sepsis_admissions AS (
  -- Admissions for male patients age 53-63 with a diagnosis containing 'sepsis' but NOT 'septic shock'
  SELECT DISTINCT a.hadm_id,
         a.subject_id,
         a.admittime,
         a.dischtime,
         a.hospital_expire_flag,
         a.admission_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON a.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON dx.icd_code = ddi.icd_code
   AND dx.icd_version = ddi.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    AND LOWER(ddi.long_title) LIKE '%sepsis%'
    AND LOWER(ddi.long_title) NOT LIKE '%septic shock%'
    AND a.hadm_id IS NOT NULL
),
hadm_flags AS (
  SELECT
    s.hadm_id,
    s.subject_id,
    s.admittime,
    s.dischtime,
    s.hospital_expire_flag,
    -- LOS in whole days (difference in days). Use this to bucket <8 vs >=8
    TIMESTAMP_DIFF(s.dischtime, s.admittime, DAY) AS los_days,
    CASE WHEN TIMESTAMP_DIFF(s.dischtime, s.admittime, DAY) < 8 THEN '<8' ELSE '>=8' END AS los_group,
    -- day-1 ICU: any icu stay intime within 24 hours of admission
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
      WHERE icu.hadm_id = s.hadm_id
        AND TIMESTAMP_DIFF(icu.intime, s.admittime, HOUR) >= 0
        AND TIMESTAMP_DIFF(icu.intime, s.admittime, HOUR) < 24
    ) THEN 'yes' ELSE 'no' END AS day1_icu,

    -- Mechanical ventilation: look in procedures_icd (billing), hcpcsevents, ICU procedureevents and chartevents (d_items labels)
    CASE WHEN (
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
          ON p.icd_code = dp.icd_code
         AND p.icd_version = dp.icd_version
        WHERE p.hadm_id = s.hadm_id
          AND (
            LOWER(dp.long_title) LIKE '%ventil%' OR LOWER(dp.long_title) LIKE '%intubat%'
          )
      )
      OR EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
        WHERE h.hadm_id = s.hadm_id
          AND (
            LOWER(h.short_description) LIKE '%ventil%' OR LOWER(h.short_description) LIKE '%intubat%'
          )
      )
      OR EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
        WHERE pe.hadm_id = s.hadm_id
          AND (
            LOWER(di.label) LIKE '%ventil%' OR LOWER(di.label) LIKE '%intubat%'
          )
          AND pe.starttime BETWEEN s.admittime AND s.dischtime
      )
      OR EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
        JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
        WHERE ce.hadm_id = s.hadm_id
          AND (
            LOWER(di.label) LIKE '%ventil%' OR LOWER(di.label) LIKE '%intubat%' OR LOWER(di.label) LIKE '%vent mode%' OR LOWER(di.label) LIKE '%ventilator%'
          )
          AND ce.charttime BETWEEN s.admittime AND s.dischtime
      )
    ) THEN 1 ELSE 0 END AS mech_vent_flag,

    -- Vasopressors: look in prescriptions and pharmacy text for common vasopressors within admission window
    CASE WHEN (
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        WHERE pr.hadm_id = s.hadm_id
          AND pr.starttime BETWEEN s.admittime AND s.dischtime
          AND (
            LOWER(pr.drug) LIKE '%norepinephrine%' OR LOWER(pr.drug) LIKE '%levophed%'
            OR LOWER(pr.drug) LIKE '%epinephrine%' OR LOWER(pr.drug) LIKE '%vasopressin%'
            OR LOWER(pr.drug) LIKE '%dopamine%' OR LOWER(pr.drug) LIKE '%phenylephrine%'
          )
      )
      OR EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
        WHERE ph.hadm_id = s.hadm_id
          AND ph.starttime BETWEEN s.admittime AND s.dischtime
          AND (
            LOWER(ph.medication) LIKE '%norepinephrine%' OR LOWER(ph.medication) LIKE '%levophed%'
            OR LOWER(ph.medication) LIKE '%epinephrine%' OR LOWER(ph.medication) LIKE '%vasopressin%'
            OR LOWER(ph.medication) LIKE '%dopamine%' OR LOWER(ph.medication) LIKE '%phenylephrine%'
          )
      )
    ) THEN 1 ELSE 0 END AS vasopressor_flag,

    -- RRT: look for dialysis/hemodialysis/renal replacement in procedure/HCPCS/ICU procedureevents/chartevents
    CASE WHEN (
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p2
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp2
          ON p2.icd_code = dp2.icd_code
         AND p2.icd_version = dp2.icd_version
        WHERE p2.hadm_id = s.hadm_id
          AND (
            LOWER(dp2.long_title) LIKE '%dialysis%' OR LOWER(dp2.long_title) LIKE '%hemodialysis%'
            OR LOWER(dp2.long_title) LIKE '%renal replacement%' OR LOWER(dp2.long_title) LIKE '%hemofiltration%'
          )
      )
      OR EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h2
        WHERE h2.hadm_id = s.hadm_id
          AND (
            LOWER(h2.short_description) LIKE '%dialysis%' OR LOWER(h2.short_description) LIKE '%hemodialysis%'
            OR LOWER(h2.short_description) LIKE '%hemofiltration%' OR LOWER(h2.short_description) LIKE '%cvvh%'
          )
      )
      OR EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe2
        JOIN `physionet-data.mimiciv_3_1_icu.d_items` di2 ON pe2.itemid = di2.itemid
        WHERE pe2.hadm_id = s.hadm_id
          AND (
            LOWER(di2.label) LIKE '%dialysis%' OR LOWER(di2.label) LIKE '%hemodialysis%'
            OR LOWER(di2.label) LIKE '%hemofiltration%' OR LOWER(di2.label) LIKE '%cvvh%'
          )
          AND pe2.starttime BETWEEN s.admittime AND s.dischtime
      )
      OR EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce2
        JOIN `physionet-data.mimiciv_3_1_icu.d_items` di3 ON ce2.itemid = di3.itemid
        WHERE ce2.hadm_id = s.hadm_id
          AND (
            LOWER(di3.label) LIKE '%dialysis%' OR LOWER(di3.label) LIKE '%hemodialysis%'
            OR LOWER(di3.label) LIKE '%hemofiltration%' OR LOWER(di3.label) LIKE '%cvvh%'
          )
          AND ce2.charttime BETWEEN s.admittime AND s.dischtime
      )
    ) THEN 1 ELSE 0 END AS rrt_flag

  FROM sepsis_admissions s
)

SELECT
  los_group,
  day1_icu,
  COUNT(*) AS n_admissions,
  100.0 * SUM(IF(hospital_expire_flag = 1, 1, 0)) / COUNT(*) AS pct_inhospital_mortality,
  100.0 * SUM(mech_vent_flag) / COUNT(*) AS pct_mechanical_ventilation,
  100.0 * SUM(vasopressor_flag) / COUNT(*) AS pct_vasopressor,
  100.0 * SUM(rrt_flag) / COUNT(*) AS pct_rrt
FROM hadm_flags
GROUP BY los_group, day1_icu
ORDER BY los_group, day1_icu;