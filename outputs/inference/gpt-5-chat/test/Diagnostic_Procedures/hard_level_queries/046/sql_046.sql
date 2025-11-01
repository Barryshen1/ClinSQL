WITH first_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
),
first_icu_filtered AS (
  SELECT
    fi.subject_id,
    fi.hadm_id,
    fi.stay_id,
    fi.intime
  FROM first_icu fi
  WHERE rn = 1
),
ards_patients AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%acute respiratory distress syndrome%'
),
patient_info AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
),
admissions_info AS (
  SELECT
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS hosp_los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
procedure_counts AS (
  SELECT
    fic.subject_id,
    fic.hadm_id,
    COUNT(DISTINCT proc.icd_code) AS distinct_proc_count
  FROM first_icu_filtered fic
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON fic.subject_id = proc.subject_id
    AND fic.hadm_id = proc.hadm_id
    AND proc.chartdate BETWEEN DATE(fic.intime) AND DATE(fic.intime + INTERVAL 3 DAY)
  GROUP BY fic.subject_id, fic.hadm_id
),
combined AS (
  SELECT
    fic.subject_id,
    fic.hadm_id,
    pi.gender,
    pi.anchor_age,
    adm.hosp_los_days,
    adm.hospital_expire_flag,
    COALESCE(pc.distinct_proc_count,0) AS distinct_proc_count,
    CASE 
      WHEN ap.subject_id IS NOT NULL THEN TRUE
      ELSE FALSE
    END AS has_ards
  FROM first_icu_filtered fic
  JOIN patient_info pi
    ON fic.subject_id = pi.subject_id
  JOIN admissions_info adm
    ON fic.hadm_id = adm.hadm_id
  LEFT JOIN procedure_counts pc
    ON fic.subject_id = pc.subject_id 
    AND fic.hadm_id = pc.hadm_id
  LEFT JOIN ards_patients ap
    ON fic.subject_id = ap.subject_id AND fic.hadm_id = ap.hadm_id
)
-- Final statistics
SELECT
  -- ARDS cohort stats
  MIN(CASE WHEN has_ards AND gender='F' AND anchor_age BETWEEN 37 AND 47 THEN distinct_proc_count END) AS min_proc_ards_female_37_47,
  -- All patients percentiles
  APPROX_QUANTILES(distinct_proc_count, 100)[OFFSET(75)] AS p75_all,
  APPROX_QUANTILES(distinct_proc_count, 100)[OFFSET(90)] AS p90_all,
  AVG(hosp_los_days) AS mean_hosp_los_all,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hosp_mortality_rate_all
FROM combined;