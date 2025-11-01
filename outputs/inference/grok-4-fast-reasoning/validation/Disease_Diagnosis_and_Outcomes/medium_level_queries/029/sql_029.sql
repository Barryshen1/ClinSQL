WITH diagnoses_all AS (
  SELECT hadm_id, icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
),
charlson_flags AS (
  SELECT hadm_id,
    MAX(CASE WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^410\..*|412')) OR
                  (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I21\..*|^I22\..*|I252'))
             THEN 1 ELSE 0 END) AS mi,
    MAX(CASE WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428\..*')) OR
                  (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'I099|I110|I130|I132|I255|^I42\..*|^I43\..*|^I50\..*|P290'))
             THEN 1 ELSE 0 END) AS chf,
    MAX(CASE WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^441\..*|785\.4|V43\.4')) OR
                  (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I70\..*|^I71\..*|I73\.1|I73\.8|I73\.9|I77\.1|I79\.0|^I97\.6.*|K55\.1|^K95\.8.*|Z95\.9'))
             THEN 1 ELSE 0 END) AS pvd,
    MAX(CASE WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^43[0-4]\..*|^43[5-8]\..*')) OR
                  (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^G45\..*|^I6[0-9]\..*|^I65\..*|^I66\..*|^I67\..*|^I68\..*|^I69\..*'))
             THEN 1 ELSE 0 END) AS cvd,
    MAX(CASE WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^290\..*|294\.1|331\.2')) OR
                  (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^F0[1-3]\..*|G30\..*'))
             THEN 1 ELSE 0 END) AS dementia,
    MAX(CASE WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'490|^491\..*|^492\..*|^493\..*|^494\..*|^495\..*|^496\..*')) OR
                  (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^J4[0-4]\..*|J45\.4|J45\.5|J45\.7|J459|^J47\..*|^J6[0-7]\..*'))
             THEN 1 ELSE 0 END) AS copd,
    MAX(CASE WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^710\..*|^714\..*|725')) OR
                  (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^M05\..*|^M06\..*|M31\.2|M31\.3|^M32\..*|^M33\..*|^M34\..*|^M35\..*|M351|M353|M36\..*'))
             THEN 1 ELSE 0 END) AS rheumatic,
    MAX(CASE WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^53[1-4]\..*|^535\..*')) OR
                  (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^K25\..*|^K26\..*|^K27\..*|^K28\..*'))
             THEN 1 ELSE 0 END) AS pud,
    MAX(CASE WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250\.[02][0-3]$')) OR
                  (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E(10|11|12|13|14)\.(0|1|9)$'))
             THEN 1 ELSE 0 END) AS dm_uncomp,
    MAX(CASE WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250\.[45][0-3]|^250\.[67][0-3]$')) OR
                  (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E(10|11|12|13|14)\.[2-8]$'))
             THEN 1 ELSE 0 END) AS dm_comp,
    MAX(CASE WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'342|343|334\.1|^344\..*|438\.2|438\.3|438\.4')) OR
                  (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^G81\..*|^G82\..*|^G83\.[0-4]$|^G86$'))
             THEN 1 ELSE 0 END) AS hemiplegia,
    MAX(CASE WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^582\..*|^583\..*|^584\..*|^585\..*|^586$|^587$|792\.5|^V42\.0|V45\.1|^V56\..*')) OR
                  (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I12\..*|^I13\..*|^N00\..*|^N01\..*|^N02\..*|^N03\..*|^N04\..*|^N05\..*|^N07\..*|^N18\..*|^N19$|^N25\.4$|^Z49\.[0-2]$|^Z94\.0$|^Z94\.2$|^Z99\.2$'))
             THEN 1 ELSE 0 END) AS renal,
    MAX(CASE WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^570$|^572\.2$|456\.2[01]|^57[0-1]\..*|456\.0|456\.1|572\.3|572\.4|572\.8|573\.3|V42\.7')) OR
                  (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I85\..*|^I86\.4$|^I86\.5$|^K70\.[0-3]$|K709|^K71\.1$|^K71\.[3-4]$|^K71\.5$|^K71\.7$|^K73\..*|^K74\..*|^B18\..*|^K76\.0$|^K76\.[2-9]$|Z94\.4'))
             THEN 1 ELSE 0 END) AS mild_liver,
    MAX(CASE WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'456\.20|456\.21|570|572\.2')) OR
                  (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'K70\.4|^K72\..*|^K73\.2$|^K74\.[3-6]$|I85\.0|I85\.1|I859'))
             THEN 1 ELSE 0 END) AS severe_liver,
    MAX(CASE WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^14[0-9]\..*|^15[0-9]\..*|^16[0-9]\..*|^17[0-2]\..*|^174\..*|^175\..*|^176\..*|^177\..*|^178\..*|^179\..*|^20[0-8]\..*')) OR
                  (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^C[0-9]{2}\..*'))
             THEN 1 ELSE 0 END) AS malignancy,
    MAX(CASE WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^19[6-9]\..*')) OR
                  (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^C77\..*|^C78\..*|^C79\..*|^C80\..*'))
             THEN 1 ELSE 0 END) AS metastatic,
    MAX(CASE WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'042|043|044')) OR
                  (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^B2[0-2]\..*|^B24\..*'))
             THEN 1 ELSE 0 END) AS aids
  FROM diagnoses_all
  GROUP BY hadm_id
),
charlson_score AS (
  SELECT hadm_id,
    mi * 1 +
    chf * 1 +
    pvd * 1 +
    cvd * 1 +
    dementia * 1 +
    copd * 1 +
    rheumatic * 1 +
    pud * 1 +
    (CASE WHEN dm_comp = 1 THEN 2 WHEN dm_uncomp = 1 THEN 1 ELSE 0 END) +
    renal * 1 +
    (CASE WHEN severe_liver = 1 THEN 2 ELSE mild_liver * 1 END) +
    (CASE WHEN metastatic = 1 THEN 3 WHEN malignancy = 1 THEN 2 ELSE 0 END) +
    hemiplegia * 2 +
    aids * 6 AS charlson
  FROM charlson_flags
),
sepsis_hadms AS (
  SELECT hadm_id,
    MAX(CASE WHEN LOWER(long_title) LIKE '%septic shock%' OR LOWER(long_title) LIKE '%severe sepsis with shock%' THEN 1 ELSE 0 END) AS is_septic_shock
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%sepsis%'
  GROUP BY hadm_id
),
base AS (
  SELECT
    hospital_expire_flag,
    gender,
    anchor_age,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days,
    charlson,
    is_septic_shock,
    CASE WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) <= 7 THEN '<=7 days' ELSE '>7 days' END AS los_bin,
    CASE WHEN charlson <= 3 THEN '<=3'
         WHEN charlson BETWEEN 4 AND 5 THEN '4-5'
         ELSE '>5' END AS charlson_bin
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN sepsis_hadms sh ON a.hadm_id = sh.hadm_id
  JOIN charlson_score cs ON a.hadm_id = cs.hadm_id
  WHERE gender = 'F'
    AND anchor_age BETWEEN 57 AND 67
    AND dischtime IS NOT NULL
),
stats AS (
  SELECT
    los_bin,
    charlson_bin,
    SUM(CASE WHEN is_septic_shock = 0 THEN hospital_expire_flag ELSE 0 END) AS deaths_sepsis,
    SUM(CASE WHEN is_septic_shock = 0 THEN 1 ELSE 0 END) AS total_sepsis,
    SUM(CASE WHEN is_septic_shock = 1 THEN hospital_expire_flag ELSE 0 END) AS deaths_shock,
    SUM(CASE WHEN is_septic_shock = 1 THEN 1 ELSE 0 END) AS total_shock
  FROM base
  GROUP BY los_bin, charlson_bin
)
SELECT
  los_bin,
  charlson_bin,
  deaths_sepsis,
  total_sepsis,
  ROUND(100.0 * deaths_sepsis / NULLIF(total_sepsis, 0), 2) AS mort_pct_sepsis,
  deaths_shock,
  total_shock,
  ROUND(100.0 * deaths_shock / NULLIF(total_shock, 0), 2) AS mort_pct_shock,
  ROUND(ABS( (100.0 * deaths_sepsis / NULLIF(total_sepsis, 0)) - (100.0 * deaths_shock / NULLIF(total_shock, 0)) ), 2) AS abs_diff_pct,
  ROUND( ((100.0 * deaths_sepsis / NULLIF(total_sepsis, 0)) - (100.0 * deaths_shock / NULLIF(total_shock, 0))) / NULLIF((100.0 * deaths_shock / NULLIF(total_shock, 0)), 0), 4) AS rel_diff
FROM stats
ORDER BY los_bin, charlson_bin;