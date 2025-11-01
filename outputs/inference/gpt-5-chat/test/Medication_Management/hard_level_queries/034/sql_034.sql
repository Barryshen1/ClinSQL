WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    -- compute age at admission
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  -- surgical admissions: service containing 'SURG'
  JOIN (
    SELECT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.services`
    WHERE UPPER(curr_service) LIKE '%SURG%'
    GROUP BY subject_id, hadm_id
  ) surg
    ON adm.subject_id = surg.subject_id AND adm.hadm_id = surg.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 51 AND 61
),
meds_24h AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    -- Identify high risk drug flags
    COUNT(DISTINCT CASE
      WHEN REGEXP_CONTAINS(UPPER(drug), r'HEPARIN|WARFARIN|INSULIN|MORPHINE|FENTANYL|OXYCODONE') 
           THEN NULL ELSE drug END) AS regular_drug_count,
    COUNT(DISTINCT CASE
      WHEN REGEXP_CONTAINS(UPPER(drug), r'HEPARIN|WARFARIN|INSULIN|MORPHINE|FENTANYL|OXYCODONE') 
           THEN drug END) AS highrisk_drug_count
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
  WHERE p.starttime >= c.admittime
    AND p.starttime < DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
    AND drug IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id
),
complexity AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COALESCE(m.regular_drug_count, 0) + COALESCE(m.highrisk_drug_count, 0)*2 AS complexity_score,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag
  FROM cohort c
  LEFT JOIN meds_24h m
    ON c.subject_id = m.subject_id AND c.hadm_id = m.hadm_id
),
with_quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY complexity_score) AS complexity_quartile
  FROM complexity
),
readmissions AS (
  SELECT
    cur.subject_id,
    cur.hadm_id,
    MIN(next.admittime) AS next_admit
  FROM complexity cur
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` next
    ON cur.subject_id = next.subject_id
    AND next.admittime > cur.dischtime
  GROUP BY cur.subject_id, cur.hadm_id
),
final AS (
  SELECT
    wq.complexity_quartile,
    COUNT(*) AS admission_count,
    AVG(TIMESTAMP_DIFF(wq.dischtime, wq.admittime, HOUR)/24.0) AS avg_los_days,
    100 * AVG(CAST(wq.hospital_expire_flag AS FLOAT64)) AS in_hosp_mortality_pct,
    100 * AVG(
      CASE WHEN ra.next_admit IS NOT NULL
             AND DATETIME_DIFF(ra.next_admit, wq.dischtime, DAY) <= 30
           THEN 1 ELSE 0 END
    ) AS readmit_30d_pct
  FROM with_quartiles wq
  LEFT JOIN readmissions ra
    ON wq.subject_id = ra.subject_id AND wq.hadm_id = ra.hadm_id
  GROUP BY wq.complexity_quartile
  ORDER BY wq.complexity_quartile
)
SELECT * FROM final;