WITH cohort AS (
  SELECT 
    adm.hadm_id,
    adm.subject_id,
    icu.stay_id,
    icu.intime,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    pat.gender = 'M'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 48 AND 58
    AND diag.icd_version IN (9, 10)
    AND (
      (diag.icd_version = 9 AND diag.icd_code IN ('5780', '5781', '5789'))
      OR 
      (diag.icd_version = 10 AND diag.icd_code IN (
        'K920', 'K921', 'K922',
        'K250', 'K251', 'K252', 'K253', 'K254', 'K255', 'K256', 'K257',
        'K260', 'K261', 'K262', 'K263', 'K264', 'K265', 'K266', 'K267',
        'K270', 'K271', 'K272', 'K273', 'K274', 'K275', 'K276', 'K277',
        'K280', 'K281', 'K282', 'K283', 'K284', 'K285', 'K286', 'K287'
      ))
    )
    AND adm.dischtime IS NOT NULL
),
procedure_counts AS (
  SELECT 
    c.stay_id,
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.intime,
    COUNT(proc.stay_id) AS proc_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` proc
    ON c.stay_id = proc.stay_id
    AND proc.starttime >= c.intime
    AND proc.starttime <= c.intime + INTERVAL '24' HOUR
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON proc.itemid = d.itemid
    AND (
      d.label LIKE '%endoscop%' 
      OR d.label LIKE '%gastroscop%' 
      OR d.label LIKE '%esophag%' 
      OR d.label LIKE '%EGD%'
    )
  GROUP BY c.stay_id, c.hadm_id, c.subject_id, c.admittime, c.dischtime, c.hospital_expire_flag, c.intime
),
quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM procedure_counts
)
SELECT
  quintile,
  AVG(proc_count) AS avg_procedures,
  AVG(DATETIME_DIFF(dischtime, admittime, SECOND) / (24 * 60 * 60)) AS avg_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_pct
FROM quintiles
GROUP BY quintile
ORDER BY quintile;