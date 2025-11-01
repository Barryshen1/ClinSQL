WITH ugib_icustays AS (
  -- 1) Select male ICU stays aged 48-58 with at least one UGIB diagnosis
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      USING (subject_id, hadm_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    -- require at least one UGIB diagnosis on this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        USING (icd_code, icd_version)
      WHERE
        di.subject_id = p.subject_id
        AND di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%gi bleed%'
        AND LOWER(dd.long_title) LIKE '%upper%'
    )
),
proc_counts AS (
  -- 2) Count diagnostic procedures in first 24h of each ICU stay
  SELECT
    u.stay_id,
    COUNT(*) AS proc_count
  FROM
    ugib_icustays u
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
      ON pr.subject_id = u.subject_id
      AND pr.hadm_id = u.hadm_id
      -- restrict to procedures in the first 24h of ICU stay
      AND pr.chartdate BETWEEN DATE(u.intime)
                         AND DATE(TIMESTAMP_ADD(u.intime, INTERVAL 1 DAY))
  GROUP BY
    u.stay_id
),
with_quintiles AS (
  -- 3) Assign quintile based on proc_count
  SELECT
    u.stay_id,
    u.los,
    u.hospital_expire_flag,
    pc.proc_count,
    NTILE(5) OVER (ORDER BY pc.proc_count) AS quintile
  FROM
    ugib_icustays u
    JOIN proc_counts pc
      USING (stay_id)
)
-- 4) Aggregate by quintile
SELECT
  quintile,
  COUNT(*)                                AS n_stays,
  ROUND(AVG(proc_count), 2)               AS avg_procedures,
  ROUND(AVG(los), 2)                      AS avg_icu_los_days,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) 
        / COUNT(*), 1)                    AS in_hospital_mortality_pct
FROM
  with_quintiles
GROUP BY
  quintile
ORDER BY
  quintile;