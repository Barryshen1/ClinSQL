WITH vasopressor_stays AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` AS ie
    ON ie.stay_id = icu.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = ie.itemid
  WHERE (
        LOWER(di.label) LIKE '%norepinephrine%' OR
        LOWER(di.label) LIKE '%epinephrine%' OR
        LOWER(di.label) LIKE '%phenylephrine%' OR
        LOWER(di.label) LIKE '%vasopressin%' OR
        LOWER(di.label) LIKE '%dopamine%'
      )
    AND ie.starttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 72 HOUR)
),
cohort AS (
  SELECT
    vs.subject_id,
    vs.hadm_id,
    vs.stay_id,
    vs.intime
  FROM vasopressor_stays vs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON vs.subject_id = p.subject_id
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 68 AND 78
),
diag_and_proc AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    -- Labs within 72h
    (
      SELECT COUNT(*) FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
      WHERE le.hadm_id = c.hadm_id
        AND le.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
    ) AS labs_72h,
    -- Imaging within 72h
    (
      SELECT COUNT(*) FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ce.itemid
      WHERE ce.hadm_id = c.hadm_id
        AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
        AND (
              LOWER(di.category) LIKE '%imaging%' OR
              LOWER(di.label) LIKE '%ct%' OR
              LOWER(di.label) LIKE '%mri%' OR
              LOWER(di.label) LIKE '%x-ray%' OR
              LOWER(di.label) LIKE '%radiograph%'
            )
    ) AS imaging_72h,
    -- Total diagnostic load within 72h
    (
      (
        SELECT COUNT(*) FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
        WHERE le.hadm_id = c.hadm_id
          AND le.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
      )
      +
      (
        SELECT COUNT(*) FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
        JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ce.itemid
        WHERE ce.hadm_id = c.hadm_id
          AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
          AND (
                LOWER(di.category) LIKE '%imaging%' OR
                LOWER(di.label) LIKE '%ct%' OR
                LOWER(di.label) LIKE '%mri%' OR
                LOWER(di.label) LIKE '%x-ray%' OR
                LOWER(di.label) LIKE '%radiograph%'
              )
      )
    ) AS diag_load_72h,
    -- Procedure count within 72h
    (
      SELECT COUNT(*) FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE pe.hadm_id = c.hadm_id
        AND pe.starttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
    ) AS proc_72h
  FROM cohort c
),
joined AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.stay_id,
    d.intime,
    d.diag_load_72h,
    d.proc_72h,
    adm.dischtime,
    adm.admittime,
    adm.hospital_expire_flag AS in_hospital_mortality
  FROM diag_and_proc d
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON adm.hadm_id = d.hadm_id
),
augmented AS (
  SELECT
    j.subject_id,
    j.hadm_id,
    j.stay_id,
    j.intime,
    j.dischtime,
    j.admittime,
    j.diag_load_72h,
    j.proc_72h,
    j.in_hospital_mortality,
    TIMESTAMP_DIFF(j.dischtime, j.admittime, SECOND) / 3600.0 AS hospital_los_hours,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = j.subject_id
          AND a2.admittime > j.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(j.dischtime, INTERVAL 30 DAY)
      )
      THEN 1 ELSE 0
    END AS readmit_30
  FROM joined j
),
quartile_calc AS (
  SELECT
    a.*,
    NTILE(4) OVER (ORDER BY diag_load_72h) AS quartile
  FROM augmented a
)

SELECT
  quartile,
  AVG(proc_72h) AS avg_proc_72h,
  AVG(hospital_los_hours) AS avg_hospital_los_hours,
  AVG(in_hospital_mortality) AS in_hospital_mortality_rate,
  AVG(readmit_30) AS readmission_30d_rate
FROM quartile_calc
GROUP BY quartile
ORDER BY quartile;