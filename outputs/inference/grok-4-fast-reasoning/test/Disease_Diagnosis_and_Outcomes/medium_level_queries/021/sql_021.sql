WITH base_cohort AS (
  -- Select unique admissions for male patients aged 60-70 with postoperative complications
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND (
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^99[6-9]'))
      OR
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^T8[0-8]'))
    )
),

with_icu AS (
  -- Flag ICU admissions (any icustay during hadm)
  SELECT
    bc.*,
    CASE WHEN COUNT(i.stay_id) > 0 THEN 1 ELSE 0 END AS is_icu
  FROM base_cohort bc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON bc.subject_id = i.subject_id AND bc.hadm_id = i.hadm_id
  GROUP BY
    bc.subject_id, bc.hadm_id, bc.gender, bc.anchor_age,
    bc.admittime, bc.dischtime, bc.deathtime, bc.hospital_expire_flag
),

with_los AS (
  -- Calculate LOS in days
  SELECT
    w.*,
    TIMESTAMP_DIFF(w.dischtime, w.admittime, DAY) AS los_days
  FROM with_icu w
),

charlson_scores AS (
  -- Calculate Charlson score per hadm_id (Quan/Deyo; full conditions below)
  SELECT
    di.hadm_id,
    SUM(
      -- MI (weight 1)
      CASE
        WHEN di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^(410|412)') THEN 1
        WHEN di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^(I21|I22|I25\.2)') THEN 1
        ELSE 0
      END +
      -- CHF (weight 1)
      CASE
        WHEN di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^428') THEN 1
        WHEN di.icd_version = 10 AND (
          REGEXP_CONTAINS(di.icd_code, r'^I09\.9') OR REGEXP_CONTAINS(di.icd_code, r'^I11\.0') OR
          REGEXP_CONTAINS(di.icd_code, r'^I13\.0') OR REGEXP_CONTAINS(di.icd_code, r'^I13\.2') OR REGEXP_CONTAINS(di.icd_code, r'^I25\.5') OR
          REGEXP_CONTAINS(di.icd_code, r'^I42\.0') OR REGEXP_CONTAINS(di.icd_code, r'^I42\.[5-9]') OR
          REGEXP_CONTAINS(di.icd_code, r'^I43') OR REGEXP_CONTAINS(di.icd_code, r'^I50') OR REGEXP_CONTAINS(di.icd_code, r'^P29\.0')
        ) THEN 1
        ELSE 0
      END +
      -- Peripheral vascular disease (weight 1)
      CASE
        WHEN di.icd_version = 9 AND (
          REGEXP_CONTAINS(di.icd_code, r'^44[0-2]') OR
          REGEXP_CONTAINS(di.icd_code, r'^443[1-9]') OR REGEXP_CONTAINS(di.icd_code, r'^7854') OR REGEXP_CONTAINS(di.icd_code, r'^V434$')
        ) THEN 1
        WHEN di.icd_version = 10 AND (
          REGEXP_CONTAINS(di.icd_code, r'^I70') OR REGEXP_CONTAINS(di.icd_code, r'^I71') OR
          REGEXP_CONTAINS(di.icd_code, r'^(I73\.1|I73\.8|I73\.9|I77\.1|I79\.0|K55\.1|Z95\.9)')
        ) THEN 1
        ELSE 0
      END +
      -- Dementia (weight 1)
      CASE
        WHEN di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^290') THEN 1
        WHEN di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^(F01|F02|F03)') THEN 1
        ELSE 0
      END +
      -- COPD (weight 1)
      CASE
        WHEN di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^(490|491|492|493|494|495|496)') THEN 1
        WHEN di.icd_version = 10 AND (
          REGEXP_CONTAINS(di.icd_code, r'^(J4[0-4]|J47|J6[0-7])')
        ) THEN 1
        ELSE 0
      END +
      -- Connective tissue/rheumatic disease (weight 1)
      CASE
        WHEN di.icd_version = 9 AND (
          REGEXP_CONTAINS(di.icd_code, r'^710[0-4]') OR REGEXP_CONTAINS(di.icd_code, r'^7109$') OR
          REGEXP_CONTAINS(di.icd_code, r'^71[1-2][2-9]') OR REGEXP_CONTAINS(di.icd_code, r'^712') OR
          REGEXP_CONTAINS(di.icd_code, r'^7131$') OR REGEXP_CONTAINS(di.icd_code, r'^714') OR REGEXP_CONTAINS(di.icd_code, r'^725$')
        ) THEN 1
        WHEN di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^(M05|M06|M08|M1[2-3]|M3[2-6]|M31\.5)') THEN 1
        ELSE 0
      END +
      -- Peptic ulcer disease (weight 1)
      CASE
        WHEN di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^(531|532|533|534)') THEN 1
        WHEN di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^K2[5-8]') THEN 1
        ELSE 0
      END +
      -- Mild liver disease (weight 1)
      CASE
        WHEN di.icd_version = 9 AND (REGEXP_CONTAINS(di.icd_code, r'^570$') OR REGEXP_CONTAINS(di.icd_code, r'^571[3-6]')) THEN 1
        WHEN di.icd_version = 10 AND (
          REGEXP_CONTAINS(di.icd_code, r'^(B18|I85|I86|I98|K70|K71\.[0-3]|K73|K74|K76|Z94\.4)')
        ) THEN 1
        ELSE 0
      END +
      -- Diabetes without complications (weight 1)
      CASE
        WHEN di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^250[0-2](0|2)') THEN 1  -- Simplified; 5th digit 0/2
        WHEN di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^(E(10|11|12|13|14)\.(0|1|9)|O24\.(0|4))') THEN 1
        ELSE 0
      END +
      -- Diabetes with complications (weight 2)
      CASE
        WHEN di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^250[0-3](1|3)') THEN 2  -- 5th digit 1/3
        WHEN di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^E(10|11|12|13|14)\.(2|3|4|5|6|7|8)') THEN 2  -- Chronic/end-organ
        ELSE 0
      END +
      -- Paraplegia/hemiplegia (weight 2)
      CASE
        WHEN di.icd_version = 9 AND (
          REGEXP_CONTAINS(di.icd_code, r'^(342|343|344[01])') OR
          REGEXP_CONTAINS(di.icd_code, r'^344[3-9]')
        ) THEN 2
        WHEN di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^(G81[1-2]|G82|G83[0-4])') THEN 2
        ELSE 0
      END +
      -- Renal disease (weight 2)
      CASE
        WHEN di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^(582|583|585|586|V42|V43|V451[1-2]|V56)') THEN 2
        WHEN di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^(I12|I13|N18|N19|Z94\.0|Z99\.2)') THEN 2
        ELSE 0
      END +
      -- Cancer (weight 2; exclude non-met)
      CASE
        WHEN di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^(14[0-9]|15[0-9]|16[0-9]|17[0-9])') THEN 2  -- Simplified solid tumors
        WHEN di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^(C0[0-9]|C[1-7][0-9]|C8[0-1])') THEN 2
        ELSE 0
      END +
      -- Moderate/severe liver disease (weight 3)
      CASE
        WHEN di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^(456[0-2]|572[2-4])') THEN 3
        WHEN di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^(I85\.[1-9]|I86\.4|I98\.0|K70\.4|K72\.[1-4]|K76\.6|R1[8-9]\.0)') THEN 3
        ELSE 0
      END +
      -- Metastatic cancer (weight 6)
      CASE
        WHEN di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^(19[6-8])') THEN 6
        WHEN di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^(C77|C78|C79|C80)') THEN 6
        ELSE 0
      END +
      -- AIDS (weight 6)
      CASE
        WHEN di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^(042|043|044)') THEN 6
        WHEN di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^B[2-4]') THEN 6  -- Simplified
        ELSE 0
      END
    ) AS charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  GROUP BY di.hadm_id
),

with_charlson AS (
  -- Join Charlson scores (default 0 if none)
  SELECT
    wl.*,
    COALESCE(cs.charlson_score, 0) AS charlson_score
  FROM with_los wl
  LEFT JOIN charlson_scores cs
    ON wl.hadm_id = cs.hadm_id
),

with_bins AS (
  -- Bin LOS and Charlson
  SELECT
    *,
    CASE
      WHEN los_days <= 3 THEN '1-3'
      WHEN los_days <= 7 THEN '4-7'
      ELSE '>=8'
    END AS los_bin,
    CASE
      WHEN charlson_score <= 3 THEN '<=3'
      WHEN charlson_score <= 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_bin
  FROM with_charlson
),

summary AS (
  -- Main aggregates: N, deaths, mortality %
  SELECT
    is_icu,
    los_bin,
    charlson_bin,
    COUNT(hadm_id) AS N,
    SUM(CAST(hospital_expire_flag AS INT64)) AS num_deaths,
    ROUND(AVG(CAST(hospital_expire_flag AS INT64)) * 100, 2) AS mortality_pct
  FROM with_bins
  GROUP BY is_icu, los_bin, charlson_bin
),

decedents AS (
  -- TTD for decedents only
  SELECT
    is_icu,
    los_bin,
    charlson_bin,
    TIMESTAMP_DIFF(deathtime, admittime, DAY) AS ttd_days
  FROM with_bins
  WHERE hospital_expire_flag = 1
),

median_ttd AS (
  -- Median TTD per group (approx; NULL if no decedents)
  SELECT
    is_icu,
    los_bin,
    charlson_bin,
    APPROX_QUANTILES(ttd_days, 2)[OFFSET(1)] AS median_ttd_days
  FROM decedents
  GROUP BY is_icu, los_bin, charlson_bin
)

-- Final join and output
SELECT
  CASE WHEN s.is_icu = 1 THEN 'ICU' ELSE 'non-ICU' END AS cohort,
  s.los_bin,
  s.charlson_bin,
  s.N,
  s.mortality_pct,
  m.median_ttd_days
FROM summary s
LEFT JOIN median_ttd m
  ON s.is_icu = m.is_icu
  AND s.los_bin = m.los_bin
  AND s.charlson_bin = m.charlson_bin
ORDER BY s.is_icu, s.los_bin, s.charlson_bin;