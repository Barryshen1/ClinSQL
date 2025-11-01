WITH aki_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'N17%') -- AKI ICD-10
      OR (d.icd_version = 9 AND d.icd_code LIKE '584%') -- AKI ICD-9
    )
),
comorbs AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    COUNT(DISTINCT CONCAT(dx.icd_version,'-',dx.icd_code)) AS comorb_count,
    MAX(
      CASE
        WHEN (dx.icd_version = 10 AND dx.icd_code = 'J80')
          OR (dx.icd_version = 9 AND dx.icd_code = '51882')
        THEN 1 ELSE 0
      END
    ) AS ards_flag
  FROM aki_admissions adm
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  WHERE NOT ((dx.icd_version = 10 AND dx.icd_code LIKE 'N17%')
             OR (dx.icd_version = 9 AND dx.icd_code LIKE '584%')) -- exclude AKI for comorb count
  GROUP BY adm.subject_id, adm.hadm_id
),
risk_scored AS (
  SELECT
    adm.*,
    c.comorb_count,
    c.ards_flag,
    (5 * c.comorb_count + CASE WHEN c.ards_flag = 1 THEN 50 ELSE 0 END) AS composite_risk,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
    CASE
      WHEN adm.hospital_expire_flag = 0
       AND adm.dod IS NOT NULL
       AND DATE(adm.dod) > DATE(adm.dischtime)
       AND DATE(adm.dod) <= DATE(adm.dischtime) + INTERVAL 30 DAY
      THEN 1 ELSE 0
    END AS mort30_flag
  FROM aki_admissions adm
  JOIN comorbs c
    ON adm.subject_id = c.subject_id
   AND adm.hadm_id = c.hadm_id
),
quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY composite_risk) AS risk_quintile
  FROM risk_scored
)
SELECT
  risk_quintile,
  COUNT(*) AS N,
  100 * SUM(mort30_flag)/COUNT(*) AS mort30_pct,
  100 * SUM(ards_flag)/COUNT(*) AS ards_pct,
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_survivor_los_days
FROM quintiles
WHERE mort30_flag = 0 -- survivors only for median LOS
GROUP BY risk_quintile
ORDER BY risk_quintile;