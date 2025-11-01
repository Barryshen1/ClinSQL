with cohort as (
  select
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  from
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    join `physionet-data.mimiciv_3_1_hosp.patients` p
      using(subject_id)
  where
    p.gender = 'F'
    and p.anchor_age between 86 and 96
    and exists (
      select 1
      from `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      where d.hadm_id = a.hadm_id
        and (
          -- Diabetes: ICD-9 250.* or ICD-10 E10*, E11*
          d.icd_code like '250%' OR d.icd_code like 'E10%' OR d.icd_code like 'E11%'
        )
    )
    and exists (
      select 1
      from `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      where d.hadm_id = a.hadm_id
        and (
          -- Heart failure: ICD-9 428.* or ICD-10 I50*
          d.icd_code like '428%' OR d.icd_code like 'I50%'
        )
    )
),

-- Precompute window boundaries for each admission
windows as (
  select
    c.*,
    TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR) as early_end,
    TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR) as late_start
  from cohort c
),

-- Pull prescriptions (uppercased drug text) for joins
rx as (
  select
    p.hadm_id,
    p.starttime,
    p.stoptime,
    upper(coalesce(p.drug, '')) as drug
  from
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
),

-- For each prescription row mark whether it is insulin or oral agent (based on name patterns)
rx_classified as (
  select
    r.*,
    case
      when (
        r.drug like '%INSULIN%' OR r.drug like '%LANTUS%' OR r.drug like '%LEVEMIR%' OR r.drug like '%NOVOLOG%'
        OR r.drug like '%HUMULIN%' OR r.drug like '%HUMALOG%' OR r.drug like '%TOUJEO%' OR r.drug like '%TRESIBA%'
        OR r.drug like '%APIDRA%'
      ) then 1 else 0 end as is_insulin,
    case
      when (
        r.drug like '%METFORMIN%' OR r.drug like '%GLIPIZIDE%' OR r.drug like '%GLYBURIDE%' OR r.drug like '%GLIMEPIRIDE%'
        OR r.drug like '%SITAGLIPTIN%' OR r.drug like '%SAXAGLIPTIN%' OR r.drug like '%LINAGLIPTIN%' OR r.drug like '%ALOGLIPTIN%'
        OR r.drug like '%PIOGLITAZONE%' OR r.drug like '%REPAGLINIDE%' OR r.drug like '%NATEGLINIDE%' OR r.drug like '%ACARBOSE%'
        OR r.drug like '%MIGLITOL%' OR r.drug like '%DPP%' OR r.drug like '%SGLT2%' OR r.drug like '%JARDIANCE%' OR r.drug like '%JANUVIA%'
        OR r.drug like '%ACTOS%' OR r.drug like '%GLUCOTROL%' OR r.drug like '%AMARYL%' OR r.drug like '%GLUCOPAGE%'
      ) then 1 else 0 end as is_oral
  from rx r
),

-- Aggregate per admission to determine presence in early and late windows for each class
med_presence as (
  select
    w.hadm_id,
    w.admittime,
    w.dischtime,
    -- early window: [admittime, early_end]
    -- late  window: [late_start, dischtime]
    coalesce(max(case when rc.is_insulin = 1
          and rc.starttime <= w.early_end
          and coalesce(rc.stoptime, w.dischtime) >= w.admittime
        then 1 else 0 end), 0) as early_insulin,
    coalesce(max(case when rc.is_oral = 1
          and rc.starttime <= w.early_end
          and coalesce(rc.stoptime, w.dischtime) >= w.admittime
        then 1 else 0 end), 0) as early_oral,
    coalesce(max(case when rc.is_insulin = 1
          and rc.starttime <= w.dischtime
          and coalesce(rc.stoptime, w.dischtime) >= w.late_start
        then 1 else 0 end), 0) as late_insulin,
    coalesce(max(case when rc.is_oral = 1
          and rc.starttime <= w.dischtime
          and coalesce(rc.stoptime, w.dischtime) >= w.late_start
        then 1 else 0 end), 0) as late_oral
  from
    windows w
    left join rx_classified rc
      on rc.hadm_id = w.hadm_id
  group by w.hadm_id, w.admittime, w.dischtime
),

-- Make categorical early/late statuses for transition matrix
med_categories as (
  select
    mp.*,
    case
      when mp.early_insulin = 1 and mp.early_oral = 1 then 'Both'
      when mp.early_insulin = 1 then 'Insulin only'
      when mp.early_oral = 1 then 'Oral only'
      else 'Neither'
    end as early_status,
    case
      when mp.late_insulin = 1 and mp.late_oral = 1 then 'Both'
      when mp.late_insulin = 1 then 'Insulin only'
      when mp.late_oral = 1 then 'Oral only'
      else 'Neither'
    end as late_status
  from med_presence mp
),

total_count as (
  select count(*) as total from med_categories
)

-- Final outputs:
-- 1) Class-level early and late rates
-- 2) Transition matrix early_status -> late_status counts and percentages
select
  'class_rate' as report_type,
  class_name as metric,
  period as period,
  count_in_period as count,
  round(100.0 * count_in_period / t.total, 2) as percent_of_cohort
from (
  -- insulin early/late counts
  select 'Insulin' as class_name, 'early (first 12h)' as period, sum(early_insulin) as count_in_period from med_categories union all
  select 'Insulin', 'late (final 72h)', sum(late_insulin) from med_categories union all
  select 'Oral Agents', 'early (first 12h)', sum(early_oral) from med_categories union all
  select 'Oral Agents', 'late (final 72h)', sum(late_oral) from med_categories
) cr
cross join total_count t

union all

select
  'transition' as report_type,
  concat(early_status, ' -> ', late_status) as metric,
  null as period,
  cnt as count,
  round(100.0 * cnt / t.total, 2) as percent_of_cohort
from (
  select early_status, late_status, count(*) as cnt
  from med_categories
  group by early_status, late_status
  order by cnt desc
) mt
cross join total_count t
order by report_type, metric;