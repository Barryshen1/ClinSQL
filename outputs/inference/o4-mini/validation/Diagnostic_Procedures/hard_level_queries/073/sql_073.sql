WITH first_icu AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los
  FROM (
    SELECT
      subject_id,
      hadm_id,
      stay_id,
      intime,
      outtime,
      los,
      ROW_NUMBER() OVER(PARTITION BY subject_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  )
  WHERE rn = 1
),
hepatic_admissions AS (
  -- Hospital admissions with hepatic failure diagnosis
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
    AND d.icd_version = dicd.icd_version
  WHERE LOWER(dicd.long_title) LIKE '%hepatic failure%'
),
proc_counts AS (
  -- Count distinct diagnostic procedure itemids in first 72h of ICU
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM first_icu f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.subject_id = f.subject_id
   AND pe.hadm_id = f.hadm_id
   AND pe.stay_id = f.stay_id
   AND pe.starttime BETWEEN f.intime
                        AND TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR)
  GROUP BY
    f.subject_id,
    f.hadm_id,
    f.stay_id
),
patient_stats AS (
  -- Assemble patient-level stats
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.stay_id,
    pc.proc_count,
    fi.los,
    adm.hospital_expire_flag
  FROM proc_counts pc
  JOIN first_icu fi
    ON pc.subject_id = fi.subject_id
   AND pc.hadm_id = fi.hadm_id
   AND pc.stay_id = fi.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pc.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pc.subject_id = p.subject_id
  JOIN hepatic_admissions ha
    ON pc.subject_id = ha.subject_id
   AND pc.hadm_id = ha.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
),
quartiled AS (
  -- Assign quartiles by procedure count
  SELECT
    *,
    NTILE(4) OVER (ORDER BY proc_count) AS quartile
  FROM patient_stats
)
SELECT
  quartile,
  COUNT(*) AS num_patients,
  MIN(proc_count) AS min_proc,
  MAX(proc_count) AS max_proc,
  ROUND(AVG(proc_count), 2) AS mean_proc,
  ROUND(AVG(los), 2) AS mean_los_days,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2)
    AS in_hospital_mortality_pct
FROM quartiled
GROUP BY quartile
ORDER BY quartile;